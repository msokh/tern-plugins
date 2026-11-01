--!strict
local canon = require("./canon")
local config = require("./config")
local events = require("./events")
local paths = require("./paths")
local raw = require("./raw")
local runner = require("./runner")
local schedule = require("./schedule")


export type ProcessOpts = { cwd: string?, env: { [string]: string }?, timeout_ms: number? }
export type ProcessOut = { status: number, stdout: string, stderr: string, timed_out: boolean }
export type PaneExit = { pane: number, status: number }

export type Host = {
	json: { encode: (value: unknown, pretty: boolean?) -> string, decode: (text: string) -> unknown },
	fs: {
		read: (path: string, max_bytes: number?) -> string,
		write: (path: string, text: string) -> (),
		list: (path: string) -> { string },
		exists: (path: string) -> boolean,
		mkdir: (path: string) -> (),
		remove: (path: string) -> (),
	},
	kv: { get: (key: string) -> unknown, set: (key: string, value: unknown) -> () },
	process: { run: (argv: { string }, opts: ProcessOpts, cb: (result: ProcessOut) -> ()) -> () },
	timer: (ms: number, fn: () -> ()) -> unknown,
	on: (name: string, fn: (ev: PaneExit) -> ()) -> (),
	pane: { list: () -> { { pane: number } } },
	log: { warn: (...unknown) -> (), error: (...unknown) -> () },
}

export type Clock = {
	time: () -> number,
	date: (epoch: number) -> schedule.Date,
	format: (fmt: string, epoch: number) -> string,
	mono: () -> number,
}

export type Env = { host: Host, paths: paths.Paths, clock: Clock, pluginDir: string }

export type Run = {
	key: string,
	trigger: string,
	at: number,
	session: string,
	phase: string,
	status: number?,
	detail: string?,
	endedAt: number?,
	pane: number?,
}

export type RunView = {
	key: string,
	id: string,
	automationId: string,
	automationName: string,
	trigger: string,
	at: number,
	session: string,
	phase: string,
	status: number?,
	detail: string?,
	endedAt: number?,
}

export type Snapshot = {
	definitions: { config.Definition },
	runs: { RunView },
	errors: { string },
	nextRuns: { [string]: number },
	health: string,
}

export type Runtime = {
	start: () -> (),
	snapshot: () -> Snapshot,
	save: (definition: config.Definition, expected: string?) -> (boolean, string?),
	setEnabled: (id: string, enabled: boolean, expected: string?) -> (boolean, string?),
	revision: (id: string) -> string?,
	runNow: (id: string) -> (boolean, string?),
	subscribe: (callback: () -> ()) -> () -> (),
	tick: () -> (),
}

local TICK_MS = 15 * 1000
local KEEP_RUNS = 20
local RECLAIMABLE_PHASES: { [string]: boolean } = {
	exited = true,
	launch_failed = true,
	skipped_precheck = true,
	missed = true,
}
local SHOWN_RUNS = 200
local LAUNCH_TIMEOUT_MS = 30 * 1000
local GIT_TIMEOUT_MS = 60 * 1000
local MAX_CONFIG_BYTES = 1024 * 1024
local MAX_EVENT_BYTES = 128 * 1024
local EVENTS_PER_TICK = 50
local SEEN_EVENTS = 500
local KEEP_BACKUPS = 20
local KEEP_REJECTED = 50
local MAX_EARLY_EXITS = 64
local EARLY_EXIT_TTL_MS = 120 * 1000
local CACHE_MS = 2000
local NEXT_HORIZON = 366 * 86400
local MISSED_SCAN = 7 * 86400
local MAX_EVENT_ERRORS = 20
local CONFLICT_CHANGED = "the config file changed while saving; nothing was written, try again"

local function create(env: Env): Runtime
	local host, p, clock = env.host, env.paths, env.clock
	local leaf = config.leafOf(host.json.encode)

	type Cache = {
		doc: config.Document,
		automations: { [string]: config.Automation },
		order: { string },
		nextRuns: { [string]: number },
		at: number,
	}
	local cache: Cache? = nil
	local started = false
	local recovered: { [string]: boolean } = {}
	local lastTickError: string? = nil
	local eventErrors: { string } = {}
	local earlyExits: { { pane: number, status: number, at: number } } = {}
	local listeners: { [number]: () -> () } = {}
	local nextListener = 0
	local backupSeq = 0

	local function notify()
		for _, fn in listeners do
			local ok, err = pcall(fn)
			if not ok then
				host.log.error("automations listener", err)
			end
		end
	end


	local function mkdirs(...: string)
		for _, dir in { ... } do
			pcall(host.fs.mkdir, dir)
		end
	end

	local function readConfig(): (string?, string?)
		if not host.fs.exists(p.config) then
			return nil, nil
		end
		local ok, text = pcall(host.fs.read, p.config, MAX_CONFIG_BYTES)
		if not ok then
			return nil, "cannot read the config file"
		end
		return text, nil
	end

	local function parseConfig(text: string?): config.Document
		return config.parseDocument(text, host.json.decode)
	end

	local function pruneDir(dir: string, keep: number)
		local ok, names = pcall(host.fs.list, dir)
		if not ok then
			return
		end
		for i = 1, #names - keep do
			pcall(host.fs.remove, `{dir}/{names[i]}`)
		end
	end

	local function backup(text: string): string?
		backupSeq += 1
		mkdirs(p.state, p.backups)
		local name = string.format("automations-%011d-%04d.json", clock.time(), backupSeq)
		local ok = pcall(host.fs.write, `{p.backups}/{name}`, text)
		if not ok then
			return "cannot write a backup of the config file; nothing was changed"
		end
		pruneDir(p.backups, KEEP_BACKUPS)
		return nil
	end


	local function toRun(value: unknown): Run?
		local o = raw.object(value)
		if not o then
			return nil
		end
		local key, trigger, at, session, phase = o.key, o.trigger, o.at, o.session, o.phase
		if type(key) ~= "string" or type(trigger) ~= "string" or type(at) ~= "number" or type(session) ~= "string" or type(phase) ~= "string" then
			return nil
		end
		return {
			key = key,
			trigger = trigger,
			at = at,
			session = session,
			phase = phase,
			status = if type(o.status) == "number" then o.status else nil,
			detail = if type(o.detail) == "string" then o.detail else nil,
			endedAt = if type(o.endedAt) == "number" then o.endedAt else nil,
			pane = if type(o.pane) == "number" then o.pane else nil,
		}
	end

	local function runsOf(id: string): { Run }
		local out: { Run } = {}
		local stored = raw.array(host.kv.get(`runs:{id}`))
		for _, item in stored or {} do
			local run = toRun(item)
			if run then
				table.insert(out, run)
			end
		end
		return out
	end

	local function saveRun(id: string, run: Run)
		local runs = runsOf(id)
		local replaced = false
		for i, existing in runs do
			if existing.key == run.key then
				runs[i] = run
				replaced = true
				break
			end
		end
		if not replaced then
			table.insert(runs, 1, run)
		end
		local finished, index = 0, 1
		while index <= #runs do
			local existing = runs[index]
			if RECLAIMABLE_PHASES[existing.phase] then
				finished += 1
				if finished > KEEP_RUNS then
					table.remove(runs, index)
					pcall(host.fs.remove, `{p.runs}/{runner.runName(id, existing.key)}`)
					continue
				end
			end
			index += 1
		end
		host.kv.set(`runs:{id}`, runs)
		notify()
	end

	local function conclude(id: string, run: Run, phase: string, detail: string?, status: number?)
		run.phase, run.detail, run.status, run.endedAt = phase, detail, status, clock.time()
		saveRun(id, run)
	end

	local function recover(c: Cache)
		local pending = false
		for _, id in c.order do
			if not recovered[id] then
				pending = true
				break
			end
		end
		if not pending then
			return
		end
		local live: { [number]: boolean } = {}
		local listed, panes = pcall(host.pane.list)
		if listed then
			for _, pane in panes do
				live[pane.pane] = true
			end
		end
		for _, id in c.order do
			if recovered[id] then
				continue
			end
			for _, run in runsOf(id) do
				if run.phase == "claimed" or run.phase == "preparing" then
					conclude(id, run, "interrupted", "plugin reloaded before launch finished", nil)
				elseif run.phase == "launched" and listed and run.pane and not live[run.pane] then
					host.kv.set(`pane:{run.pane}`, nil)
					conclude(id, run, "unknown", "the session ended while the plugin was not watching; its exit status was not seen", nil)
				end
			end
			recovered[id] = listed
		end
	end


	local function computeNext(a: config.Automation, now: number): number?
		local best: number? = nil
		for _, cron in a.crons do
			local slot = schedule.next(cron, now, NEXT_HORIZON, clock.date)
			if slot and (best == nil or slot < best) then
				best = slot
			end
		end
		return best
	end

	local function refresh(force: boolean): Cache
		local now = clock.mono()
		if cache and not force and now - cache.at < CACHE_MS then
			return cache
		end
		local text, err = readConfig()
		local doc = parseConfig(text)
		if err then
			doc.unsaveable = err
			table.insert(doc.errors, err)
		end
		local automations: { [string]: config.Automation } = {}
		local order: { string } = {}
		local nextRuns: { [string]: number } = {}
		local epoch = clock.time()
		for _, def in config.definitions(doc) do
			local a = config.compile(def)
			if a then
				automations[def.id] = a
				table.insert(order, def.id)
				if def.enabled then
					local slot = computeNext(a, epoch)
					if slot then
						nextRuns[def.id] = slot
					end
				end
			end
		end
		cache = { doc = doc, automations = automations, order = order, nextRuns = nextRuns, at = now }
		recover(cache)
		return cache
	end

	local function commit(mutate: (config.Document) -> (string?, string?)): (string?, string?)
		local text, err = readConfig()
		if err then
			return nil, err
		end
		local doc = parseConfig(text)
		local id, problem = mutate(doc)
		if problem then
			return nil, problem
		end
		local out = config.encodeDocument(doc, leaf)
		local again = readConfig()
		if again ~= text then
			return nil, CONFLICT_CHANGED
		end
		if text then
			local failed = backup(text)
			if failed then
				return nil, failed
			end
		end
		mkdirs(p.configDir)
		local ok = pcall(host.fs.write, p.config, out)
		if not ok then
			return nil, "cannot write the config file"
		end
		refresh(true)
		notify()
		return id or "", nil
	end

	local function minuteNow(): number
		local now = clock.time()
		return now - now % 60
	end

	local function save(definition: config.Definition, expected: string?): (boolean, string?)
		local id, err = commit(function(doc)
			return config.upsert(doc, definition, expected)
		end)
		if err then
			return false, err
		end
		if id and host.kv.get(`cursor:{id}`) == nil then
			host.kv.set(`cursor:{id}`, minuteNow())
		end
		return true, nil
	end

	local function setEnabled(id: string, enabled: boolean, expected: string?): (boolean, string?)
		local _, err = commit(function(doc)
			local ok, problem = config.toggle(doc, id, enabled, expected)
			return if ok then id else nil, problem
		end)
		if err then
			return false, err
		end
		return true, nil
	end

	local function revision(id: string): string?
		local c = cache or refresh(false)
		local entry = config.findEntry(c.doc, id)
		return if entry then entry.revision else nil
	end


	local function spawn(argv: { string }, opts: ProcessOpts, cb: (ProcessOut) -> ()): string?
		local ok, err = pcall(host.process.run, argv, opts, cb)
		return if ok then nil else tostring(err)
	end

	local function eventJson(ev: events.Event): string
		local doc: raw.Object = { id = ev.id, source = ev.source, event = ev.event, received_at = ev.receivedAt, attributes = ev.attributes }
		doc.at = ev.at
		doc.payload = ev.payload
		return canon.encode(leaf, {}, doc, true)
	end

	local function launch(a: config.Automation, run: Run, cwd: string, runDir: string, ev: events.Event?)
		local def = a.def
		local promptFile = `{runDir}/prompt.md`
		local evJson = if ev then eventJson(ev) else nil
		local wrote = pcall(function()
			if evJson then
				host.fs.write(`{runDir}/event.json`, evJson)
			end
			if def.agent ~= "command" then
				host.fs.write(promptFile, runner.promptText(def.instructions, evJson))
			end
		end)
		if not wrote then
			conclude(def.id, run, "launch_failed", "cannot write the run's prompt files", nil)
			return
		end
		local program = runner.agentArgv(def, p.home, promptFile, `{env.pluginDir}/launch.sh`)
		if def.agent == "command" and ev then
			program = runner.withEventFile(program, `{runDir}/event.json`)
		end
		local failed = spawn(runner.sessionArgv(run.session, cwd, program), { timeout_ms = LAUNCH_TIMEOUT_MS }, function(result)
			local block: unknown = nil
			if result.status == 0 then
				local ok, decoded = pcall(host.json.decode, result.stdout)
				local out = if ok then raw.object(decoded) else nil
				block = if out then out.block else nil
			end
			if type(block) ~= "number" then
				if result.timed_out then
					conclude(def.id, run, "unknown", "tern did not answer in time; the session may exist", nil)
				else
					conclude(def.id, run, "launch_failed", `tern could not start the session (exit {result.status})`, nil)
				end
				return
			end
			for i, early in earlyExits do
				if early.pane == block then
					table.remove(earlyExits, i)
					conclude(def.id, run, "exited", nil, early.status)
					return
				end
			end
			run.phase, run.pane = "launched", block
			host.kv.set(`pane:{block}`, { id = def.id, key = run.key })
			saveRun(def.id, run)
		end)
		if failed then
			conclude(def.id, run, "launch_failed", "tern could not be started", nil)
		end
	end

	local function prepare(a: config.Automation, run: Run, cwd: string, runDir: string, ev: events.Event?)
		local def = a.def
		if def.workspace ~= "worktree" then
			launch(a, run, cwd, runDir, ev)
			return
		end
		local name = runner.runName(def.id, run.key)
		local path = `{p.worktrees}/{name}`
		local function fail(detail: string)
			conclude(def.id, run, "launch_failed", detail, nil)
		end
		local err = spawn(runner.gitRootArgv(cwd), { env = runner.GIT_ENV, timeout_ms = GIT_TIMEOUT_MS }, function(root)
			local top, prefix = runner.parseRepoRoot(root.stdout)
			if root.status ~= 0 or not top or not prefix then
				fail("the folder is not inside a git repository")
				return
			end
			if host.fs.exists(path) then
				fail("the run's worktree folder already exists")
				return
			end
			mkdirs(p.state, p.worktrees)
			local started = spawn(runner.worktreeArgv(top, path, def.base_branch), { env = runner.GIT_ENV, timeout_ms = GIT_TIMEOUT_MS }, function(added)
				if added.status ~= 0 then
					fail(`git worktree add failed (exit {added.status})`)
					return
				end
				launch(a, run, path .. "/" .. prefix, runDir, ev)
			end)
			if started then
				fail("git could not be started")
			end
		end)
		if err then
			fail("git could not be started")
		end
	end

	local function startRun(a: config.Automation, trigger: string, key: string, ev: events.Event?, usePrecheck: boolean)
		local def = a.def
		for _, existing in runsOf(def.id) do
			if existing.key == key then
				return
			end
		end
		local run: Run = { key = key, trigger = trigger, at = clock.time(), session = runner.sessionName(def.id, key), phase = "claimed" }
		saveRun(def.id, run)
		local runDir = `{p.runs}/{runner.runName(def.id, key)}`
		mkdirs(p.state, p.runs, runDir)
		local cwd = if def.workspace == "none" then `{runDir}/work` else config.expand(def.cwd, p.home)
		if def.workspace == "none" then
			mkdirs(cwd)
		end
		local function go()
			run.phase = "preparing"
			saveRun(def.id, run)
			prepare(a, run, cwd, runDir, ev)
		end
		local precheck = def.precheck
		if not usePrecheck or not precheck then
			go()
			return
		end
		local err = spawn(config.expandAll(precheck.command, p.home), { cwd = cwd, timeout_ms = precheck.timeout_seconds * 1000 }, function(result)
			if result.status == 0 then
				go()
			else
				conclude(def.id, run, "skipped_precheck", if result.timed_out then "precheck timed out" else `precheck exited {result.status}`, nil)
			end
		end)
		if err then
			conclude(def.id, run, "launch_failed", "the precheck could not be started", nil)
		end
	end

	local function runNow(id: string): (boolean, string?)
		local a = refresh(true).automations[id]
		if not a then
			return false, "no such automation, or its entry has a problem to fix first"
		end
		local key = clock.format("%Y%m%d%H%M%S", clock.time()) .. "m"
		for _, existing in runsOf(id) do
			if existing.key == key then
				return false, "a run was just started; wait a second"
			end
		end
		startRun(a, "manual", key, nil, false)
		return true, nil
	end


	local function onPaneExit(ev: PaneExit)
		local owner = raw.object(host.kv.get(`pane:{ev.pane}`))
		if not owner or type(owner.id) ~= "string" or type(owner.key) ~= "string" then
			local now = clock.mono()
			for i = #earlyExits, 1, -1 do
				if now - earlyExits[i].at > EARLY_EXIT_TTL_MS then
					table.remove(earlyExits, i)
				end
			end
			table.insert(earlyExits, { pane = ev.pane, status = ev.status, at = now })
			while #earlyExits > MAX_EARLY_EXITS do
				table.remove(earlyExits, 1)
			end
			return
		end
		host.kv.set(`pane:{ev.pane}`, nil)
		for _, run in runsOf(owner.id) do
			if run.key == owner.key then
				conclude(owner.id, run, "exited", nil, ev.status)
				return
			end
		end
	end



	local function hasRun(id: string, key: string): boolean
		for _, run in runsOf(id) do
			if run.key == key then
				return true
			end
		end
		return false
	end

	local function recordMissed(a: config.Automation, trigger: string, key: string, detail: string)
		local id = a.def.id
		if hasRun(id, key) then
			return
		end
		local now = clock.time()
		saveRun(id, { key = key, trigger = trigger, at = now, session = runner.sessionName(id, key), phase = "missed", detail = detail, endedAt = now })
	end

	local function takeRequest(id: string): boolean
		local path = `{p.requests}/{id}`
		if not host.fs.exists(path) then
			return false
		end
		pcall(host.fs.remove, path)
		return true
	end

	local function evaluate(a: config.Automation, nowMin: number)
		local def = a.def
		if takeRequest(def.id) then
			runNow(def.id)
		end
		local cursorValue = host.kv.get(`cursor:{def.id}`)
		local cursor = if type(cursorValue) == "number" then cursorValue else nowMin - 60
		if nowMin <= cursor then
			return
		end
		host.kv.set(`cursor:{def.id}`, nowMin)
		if not def.enabled then
			return
		end
		local after = math.max(cursor, nowMin - def.grace_minutes * 60)
		local slot: number? = nil
		local missed: number? = nil
		for _, cron in a.crons do
			local hit = schedule.latest(cron, after, nowMin, clock.date)
			if hit and (slot == nil or hit > slot) then
				slot = hit
			end
			local late = schedule.latest(cron, math.max(cursor, after - MISSED_SCAN), after, clock.date)
			if late and (missed == nil or late > missed) then
				missed = late
			end
		end
		if slot then
			startRun(a, "scheduled", clock.format("%Y%m%d%H%M", slot), nil, true)
		elseif missed then
			recordMissed(a, "scheduled", clock.format("%Y%m%d%H%M", missed) .. "x", `the {clock.format("%Y-%m-%d %H:%M", missed)} slot passed outside the {def.grace_minutes} minute grace period`)
		end
	end

	local function eventError(message: string)
		table.insert(eventErrors, message)
		while #eventErrors > MAX_EVENT_ERRORS do
			table.remove(eventErrors, 1)
		end
	end

	local function seenList(): { string }
		local out: { string } = {}
		for _, item in raw.array(host.kv.get("events:seen")) or {} do
			if type(item) == "string" then
				table.insert(out, item)
			end
		end
		return out
	end

	local function handleEvent(c: Cache, ev: events.Event, since: number, seen: { string })
		local key = events.key(ev.source, ev.id)
		if table.find(seen, key) then
			return
		end
		table.insert(seen, key)
		while #seen > SEEN_EVENTS do
			table.remove(seen, 1)
		end
		if ev.receivedAt < since then
			return
		end
		local now = clock.time()
		for _, id in c.order do
			local a = c.automations[id]
			if a.def.enabled then
				for _, rule in a.rules do
					if rule.source == ev.source and events.matches(rule.event, rule.terms, ev) then
						local trigger = `event:{ev.source}:{ev.event}`
						if now - ev.receivedAt > a.def.grace_minutes * 60 then
							recordMissed(a, trigger, `e{key}`, "the event waited longer than the grace period before it could start")
						else
							startRun(a, trigger, `e{key}`, ev, true)
						end
						break
					end
				end
			end
		end
	end

	local function drainInbox(c: Cache)
		if not host.fs.exists(p.inbox) then
			return
		end
		local sinceValue = host.kv.get("events:since")
		local since = if type(sinceValue) == "number" then sinceValue else clock.time()
		local ok, names = pcall(host.fs.list, p.inbox)
		if not ok then
			eventError("cannot list the event inbox")
			return
		end
		local seen = seenList()
		local handled = 0
		for _, name in names do
			if handled >= EVENTS_PER_TICK then
				break
			end
			if string.match(name, "%.json$") and string.sub(name, 1, 1) ~= "." then
				handled += 1
				local path = `{p.inbox}/{name}`
				local readOk, text = pcall(host.fs.read, path, MAX_EVENT_BYTES)
				local decodeOk, decoded = false, nil
				if readOk then
					decodeOk, decoded = pcall(host.json.decode, text)
				end
				local ev, problem = nil, "unreadable"
				if decodeOk then
					ev, problem = events.parse(decoded)
				end
				if ev then
					handleEvent(c, ev, since, seen)
				else
					eventError(`event file rejected: {problem}`)
					mkdirs(p.events, p.rejected)
					if readOk then
						pcall(host.fs.write, `{p.rejected}/{name}`, text)
						pruneDir(p.rejected, KEEP_REJECTED)
					end
				end
				host.kv.set("events:seen", seen)
				pcall(host.fs.remove, path)
			end
		end
	end


	local lastStatus = ""
	local function writeStatus(c: Cache)
		local out = { "# Tern automations", "", `Config: \`{p.config}\``, "" }
		for _, err in c.doc.errors do
			table.insert(out, `- problem: {err}`)
		end
		for _, id in c.order do
			table.insert(out, `## {id}`)
			for i, run in runsOf(id) do
				if i > 5 then
					break
				end
				local status = if run.status ~= nil then ` {run.status}` else ""
				table.insert(out, `- {clock.format("%Y-%m-%d %H:%M", run.at)} {run.trigger} · {run.phase}{status} · \`{run.session}\``)
			end
			table.insert(out, "")
		end
		local text = table.concat(out, "\n")
		if text ~= lastStatus then
			mkdirs(p.state)
			pcall(host.fs.write, p.status, text)
			lastStatus = text
		end
	end

	local function tick()
		local ok, err = pcall(function()
			local c = refresh(true)
			local nowMin = minuteNow()
			for _, id in c.order do
				evaluate(c.automations[id], nowMin)
			end
			if not c.doc.unsaveable then
				drainInbox(c)
			end
			writeStatus(c)
		end)
		lastTickError = if ok then nil else tostring(err)
		if not ok then
			host.log.error("automations tick", err)
		end
		host.timer(TICK_MS, tick)
	end

	local function start()
		if started then
			return
		end
		started = true
		mkdirs(p.state, p.requests, p.runs, p.events, p.inbox)
		if type(host.kv.get("events:since")) ~= "number" then
			host.kv.set("events:since", clock.time())
		end
		host.on("pane_exited", onPaneExit)
		host.timer(0, tick)
	end

	local function snapshot(): Snapshot
		local c = refresh(true)
		local definitions: { config.Definition } = {}
		local runs: { RunView } = {}
		for _, def in config.definitions(c.doc) do
			table.insert(definitions, table.clone(def))
			for _, run in runsOf(def.id) do
				table.insert(runs, {
					key = run.key,
					id = `{def.id}:{run.key}`,
					automationId = def.id,
					automationName = def.name,
					trigger = run.trigger,
					at = run.at,
					session = run.session,
					phase = run.phase,
					status = run.status,
					detail = run.detail,
					endedAt = run.endedAt,
				})
			end
		end
		table.sort(runs, function(x, y)
			if x.at ~= y.at then
				return x.at > y.at
			end
			return x.id < y.id
		end)
		while #runs > SHOWN_RUNS do
			table.remove(runs)
		end
		local errors = table.clone(c.doc.errors)
		for _, message in eventErrors do
			table.insert(errors, message)
		end
		if lastTickError then
			table.insert(errors, "scheduler tick failed; see the Tern log")
		end
		local health = if not started then "stopped" elseif #errors > 0 then "degraded" else "ok"
		return { definitions = definitions, runs = runs, errors = errors, nextRuns = table.clone(c.nextRuns), health = health }
	end

	local function subscribe(callback: () -> ()): () -> ()
		nextListener += 1
		local id = nextListener
		listeners[id] = callback
		return function()
			listeners[id] = nil
		end
	end

	return {
		start = start,
		snapshot = snapshot,
		save = save,
		setEnabled = setEnabled,
		revision = revision,
		runNow = runNow,
		subscribe = subscribe,
		-- Exposed for tests and the palette: one scheduler pass.
		tick = tick,
	}
end

return {
	create = create,
}
