--!strict
local schedule = require("./schedule")

export type Precheck = { command: { string }, timeoutMs: number }

export type Automation = {
	id: string,
	cronText: string,
	cron: schedule.Cron,
	cwd: string,
	command: { string },
	precheck: Precheck?,
	graceMinutes: number,
	enabled: boolean,
}

local DEFAULT_GRACE_MINUTES = 60
local DEFAULT_PRECHECK_SECONDS = 60

local function expand(path: string, home: string): string
	if path == "~" then
		return home
	end
	local rest = string.match(path, "^~/(.*)$")
	return if rest then `{home}/{rest}` else path
end

local function argv(value: any, home: string): { string }?
	if type(value) ~= "table" or #value == 0 then
		return nil
	end
	local out = {}
	for _, arg in value do
		if type(arg) ~= "string" then
			return nil
		end
		table.insert(out, expand(arg, home))
	end
	return out
end

local function parseOne(raw: any, home: string): (Automation?, string?)
	if type(raw) ~= "table" then
		return nil, "entry is not an object"
	end
	local id = raw.id
	if type(id) ~= "string" or not string.match(id, "^[a-z0-9][a-z0-9-]*$") then
		return nil, `id {tostring(id)} must match [a-z0-9][a-z0-9-]*`
	end
	if type(raw.cron) ~= "string" then
		return nil, `{id}: cron is required`
	end
	local cron, cronErr = schedule.parse(raw.cron)
	if not cron then
		return nil, `{id}: {cronErr}`
	end
	local cwd = if type(raw.cwd) == "string" then expand(raw.cwd, home) else nil
	if not cwd or string.sub(cwd, 1, 1) ~= "/" then
		return nil, `{id}: cwd must be an absolute or ~/ path`
	end
	local command = argv(raw.command, home)
	if not command then
		return nil, `{id}: command must be a non-empty array of strings`
	end
	local precheck: Precheck? = nil
	if raw.precheck ~= nil then
		local pre = argv(type(raw.precheck) == "table" and raw.precheck.command, home)
		if not pre then
			return nil, `{id}: precheck.command must be a non-empty array of strings`
		end
		local seconds = raw.precheck.timeout_seconds or DEFAULT_PRECHECK_SECONDS
		if type(seconds) ~= "number" or seconds <= 0 then
			return nil, `{id}: precheck.timeout_seconds must be a positive number`
		end
		precheck = { command = pre, timeoutMs = seconds * 1000 }
	end
	local grace = raw.grace_minutes or DEFAULT_GRACE_MINUTES
	if type(grace) ~= "number" or grace < 1 then
		return nil, `{id}: grace_minutes must be at least 1`
	end
	if raw.enabled ~= nil and type(raw.enabled) ~= "boolean" then
		return nil, `{id}: enabled must be true or false`
	end
	return {
		id = id,
		cronText = raw.cron,
		cron = cron,
		cwd = cwd,
		command = command,
		precheck = precheck,
		graceMinutes = math.floor(grace),
		enabled = raw.enabled ~= false,
	}, nil
end

-- Parses the decoded config document; a bad entry is reported and left out, the rest load.
local function parse(doc: any, home: string): ({ Automation }, { string })
	local automations, errors = {}, {}
	if type(doc) ~= "table" or type(doc.automations) ~= "table" then
		return automations, { "config needs an `automations` array" }
	end
	local seen = {}
	for _, raw in doc.automations do
		local automation, err = parseOne(raw, home)
		if not automation then
			table.insert(errors, err :: string)
		elseif seen[automation.id] then
			table.insert(errors, `{automation.id}: duplicate id`)
		else
			seen[automation.id] = true
			table.insert(automations, automation)
		end
	end
	return automations, errors
end

return {
	parse = parse,
}
