--!strict
local config = require("./config")
local files = require("./files")
local schedule = require("./schedule")

type Automation = config.Automation
type Phase = "claimed" | "skipped_precheck" | "launch_failed" | "launched" | "exited" | "interrupted"
type Run = {
	key: string,
	trigger: "scheduled" | "manual",
	at: number,
	session: string,
	phase: Phase,
	status: number?,
	detail: string?,
}

local TICK_MS = 15 * 1000
local KEEP_RUNS = 20
local SHOWN_RUNS = 5
local LAUNCH_TIMEOUT_MS = 30 * 1000

local function localDate(epoch: number): schedule.Date
	return os.date("*t", epoch) :: any
end

local function stamp(epoch: number): string
	return os.date("%Y-%m-%d %H:%M", epoch) :: string
end

local function firstLine(text: string): string
	return string.match(text, "^%s*([^\n]*)") or ""
end

local function runsOf(id: string): { Run }
	return tern.kv.get(`runs:{id}`) or {}
end

local function saveRun(id: string, run: Run)
	local runs = runsOf(id)
	for i, existing in runs do
		if existing.key == run.key then
			runs[i] = run
			tern.kv.set(`runs:{id}`, runs)
			return
		end
	end
	table.insert(runs, 1, run)
	while #runs > KEEP_RUNS do
		table.remove(runs)
	end
	tern.kv.set(`runs:{id}`, runs)
end

-- A pane can exit before `tern new session` reports its block id.
local earlyExits: { [number]: number } = {}

local function launch(a: Automation, run: Run)
	local argv = { "tern", "new", "session", run.session, "--json", "--cwd", a.cwd, "--end-on-success", "--" }
	for _, arg in a.command do
		table.insert(argv, arg)
	end
	local ok, err = pcall(tern.process.run, argv, { timeout_ms = LAUNCH_TIMEOUT_MS }, function(result: ProcessResult)
		local decoded, out = pcall(tern.json.decode, result.stdout)
		local block = if result.status == 0 and decoded and type(out) == "table" then out.block else nil
		if type(block) ~= "number" then
			run.phase = "launch_failed"
			run.detail = firstLine(result.stderr ~= "" and result.stderr or result.stdout)
			saveRun(a.id, run)
			return
		end
		local exited = earlyExits[block]
		if exited then
			earlyExits[block] = nil
			run.phase, run.status = "exited", exited
		else
			run.phase = "launched"
			tern.kv.set(`pane:{block}`, { id = a.id, key = run.key })
		end
		saveRun(a.id, run)
	end)
	if not ok then
		run.phase, run.detail = "launch_failed", tostring(err)
		saveRun(a.id, run)
	end
end

local function start(a: Automation, trigger: "scheduled" | "manual", key: string)
	local run: Run = {
		key = key,
		trigger = trigger,
		at = os.time(),
		session = `auto-{a.id}-{key}`,
		phase = "claimed",
	}
	saveRun(a.id, run)
	local precheck = a.precheck
	if trigger == "manual" or not precheck then
		launch(a, run)
		return
	end
	local ok, err = pcall(tern.process.run, precheck.command, { cwd = a.cwd, timeout_ms = precheck.timeoutMs }, function(result: ProcessResult)
		if result.status == 0 then
			launch(a, run)
			return
		end
		run.phase = "skipped_precheck"
		run.detail = if result.timed_out then "precheck timed out" else `precheck exited {result.status}`
		saveRun(a.id, run)
	end)
	if not ok then
		run.phase, run.detail = "launch_failed", `precheck: {err}`
		saveRun(a.id, run)
	end
end

tern.on("pane_exited", function(ev: PaneExitedEvent)
	local owner = tern.kv.get(`pane:{ev.pane}`)
	if not owner then
		earlyExits[ev.pane] = ev.status
		return
	end
	tern.kv.set(`pane:{ev.pane}`, nil)
	for _, run in runsOf(owner.id) do
		if run.key == owner.key then
			run.phase, run.status = "exited", ev.status
			saveRun(owner.id, run)
			return
		end
	end
end)

local function takeRequest(id: string): boolean
	local path = `{files.paths.requests}/{id}`
	if not tern.fs.exists(path) then
		return false
	end
	tern.fs.remove(path)
	return true
end

local function evaluate(a: Automation, nowMin: number)
	if takeRequest(a.id) then
		start(a, "manual", os.date("%Y%m%d%H%M%S") .. "m")
	end
	local cursor = tern.kv.get(`cursor:{a.id}`) or nowMin - 60
	if nowMin <= cursor then
		return
	end
	tern.kv.set(`cursor:{a.id}`, nowMin)
	if not a.enabled then
		return
	end
	local after = math.max(cursor, nowMin - a.graceMinutes * 60)
	local slot = schedule.latest(a.cron, after, nowMin, localDate)
	if slot then
		start(a, "scheduled", os.date("%Y%m%d%H%M", slot) :: string)
	end
end

local function render(automations: { Automation }, errors: { string }): string
	local out = { "# Tern automations", "", `Config: \`{files.paths.config}\``, "" }
	if #errors > 0 then
		table.insert(out, "## Config problems")
		table.insert(out, "")
		for _, err in errors do
			table.insert(out, `- {err}`)
		end
		table.insert(out, "")
	end
	for _, a in automations do
		table.insert(out, `## {a.id}`)
		table.insert(out, "")
		table.insert(out, `\`{a.cronText}\` · {if a.enabled then "enabled" else "disabled"} · grace {a.graceMinutes} min`)
		table.insert(out, "")
		local runs = runsOf(a.id)
		if #runs == 0 then
			table.insert(out, "No runs yet.")
		end
		for i, run in runs do
			if i > SHOWN_RUNS then
				break
			end
			local status = if run.status ~= nil then ` {run.status}` else ""
			local detail = if run.detail then ` · {run.detail}` else ""
			table.insert(out, `- {stamp(run.at)} {run.trigger} · {run.phase}{status} · \`{run.session}\`{detail}`)
		end
		table.insert(out, "")
	end
	return table.concat(out, "\n")
end

local lastStatus = ""
local function writeStatus(text: string)
	if text == lastStatus then
		return
	end
	tern.fs.mkdir(string.match(files.paths.status, "^(.*)/[^/]+$") :: string)
	tern.fs.write(files.paths.status, text)
	lastStatus = text
end

-- Why: a run still `claimed` when the VM starts was cut off before its launch reported back.
local function recover(automations: { Automation })
	for _, a in automations do
		for _, run in runsOf(a.id) do
			if run.phase == "claimed" then
				run.phase, run.detail = "interrupted", "plugin reloaded before launch finished"
				saveRun(a.id, run)
			end
		end
	end
end

local recovered = false
local function tick()
	local ok, err = pcall(function()
		local automations, errors = files.loadConfig()
		if not recovered then
			recover(automations)
			recovered = true
		end
		local now = os.time()
		local nowMin = now - now % 60
		for _, a in automations do
			evaluate(a, nowMin)
		end
		writeStatus(render(automations, errors))
	end)
	if not ok then
		tern.log.error("automations tick", err)
	end
	tern.timer(TICK_MS, tick)
end

tern.fs.mkdir(files.paths.requests)
tern.timer(0, tick)
