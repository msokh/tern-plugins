--!strict
local Input = require("./input")

export type Precheck = { command: { string }, timeout_seconds: number }
export type ScheduleTrigger = { kind: "schedule", cron: string }
export type EventTrigger = { kind: "event", source: string, event: string, filter: string }
export type Trigger = ScheduleTrigger | EventTrigger

export type Definition = {
	id: string,
	name: string,
	instructions: string,
	agent: string,
	model: string,
	cwd: string,
	workspace: string,
	base_branch: string,
	command: { string },
	triggers: { Trigger },
	precheck: Precheck?,
	grace_minutes: number,
	enabled: boolean,
}

export type Run = {
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
	definitions: { Definition },
	runs: { Run },
	errors: { string },
	nextRuns: { [string]: number },
	health: string,
}

export type Runtime = {
	snapshot: () -> Snapshot,
	save: (definition: Definition, expected: string?) -> (boolean, string?),
	setEnabled: (id: string, enabled: boolean, expected: string?) -> (boolean, string?),
	runNow: (id: string) -> (boolean, string?),
	revision: (id: string) -> string?,
	subscribe: (callback: () -> ()) -> () -> (),
}

export type Choice = { id: string, label: string }

export type DraftTrigger = { uid: number, source: string }

export type Draft = {
	id: string?,
	revision: string?,
	enabled: boolean,
	agent: string,
	workspace: string,
	fields: { [string]: Input.Field },
	triggers: { DraftTrigger },
	nextUid: number,
}

export type Mode = "overview" | "editor"
export type Tab = "automations" | "runs"
export type StatusFilter = "all" | "enabled" | "paused"

export type State = {
	mode: Mode,
	tab: Tab,
	filter: StatusFilter,
	selected: string?,
	search: Input.Field,
	draft: Draft?,
	focus: string?,
	error: string?,
	notice: string?,
	noticeBad: boolean,
	discardArmed: boolean,
	snapshot: Snapshot,
	revisions: { [string]: string },
	stale: boolean,
	baseline: Draft?,
	ids: { [string]: string },
	cancel: (() -> ())?,
}

local Model = {}

local AGENTS: { Choice } = {
	{ id = "command", label = "Command" },
	{ id = "omp", label = "OMP" },
	{ id = "codex", label = "Codex" },
	{ id = "claude", label = "Claude" },
}
local WORKSPACES: { Choice } = {
	{ id = "existing", label = "Existing" },
	{ id = "none", label = "None" },
	{ id = "worktree", label = "New worktree per run" },
}
local SOURCES: { Choice } = {
	{ id = "schedule", label = "Schedule" },
	{ id = "github", label = "GitHub" },
	{ id = "webhook", label = "Webhook" },
	{ id = "slack", label = "Slack" },
	{ id = "linear", label = "Linear" },
}
local FILTERS: { Choice } = {
	{ id = "all", label = "All" },
	{ id = "enabled", label = "Enabled" },
	{ id = "paused", label = "Paused" },
}
Model.AGENTS = AGENTS
Model.WORKSPACES = WORKSPACES
Model.SOURCES = SOURCES
Model.FILTERS = FILTERS

local WORKSPACE_NOUN: { [string]: string } = {
	existing = "Existing workspace",
	none = "No workspace",
	worktree = "New worktree per run",
}

local DEFAULT_GRACE_MINUTES = 60
local DEFAULT_PRECHECK_SECONDS = 60

function Model.label(choices: { Choice }, id: string): string
	for _, choice in choices do
		if choice.id == id then
			return choice.label
		end
	end
	return id
end

function Model.workspaceLabel(id: string): string
	return WORKSPACE_NOUN[id] or id
end

local SUMMARY_CHARS = 140

-- The first line of `text`, cut to a length that reads at a glance; the editor holds the whole text.
function Model.summary(text: string): string
	local line = string.match(text, "^%s*([^\n]*)") or ""
	local length = utf8.len(line)
	if length == nil or length <= SUMMARY_CHARS then
		return line
	end
	local cut = string.sub(line, 1, utf8.offset(line, SUMMARY_CHARS + 1) - 1)
	return string.gsub(cut, "%s+$", "") .. "…"
end

function Model.emptySnapshot(): Snapshot
	return { definitions = {}, runs = {}, errors = {}, nextRuns = {}, health = "" }
end

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["\b"] = "\\b",
	["\f"] = "\\f",
}

function Model.encodeArgv(list: { string }): string
	local parts = {}
	for _, item in list do
		local escaped = string.gsub(item, '[%c"\\]', function(char: string): string
			return ESCAPES[char] or string.format("\\u%04x", string.byte(char))
		end)
		table.insert(parts, `"{escaped}"`)
	end
	return `[{table.concat(parts, ", ")}]`
end

local ARGV_HINT = 'Enter a JSON array of strings, such as ["program", "argument"].'
local UNESCAPES: { [string]: string } =
	{ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function readString(text: string, start: number): (string?, number)
	local out = {}
	local i = start + 1
	while i <= #text do
		local char = string.sub(text, i, i)
		if char == '"' then
			return table.concat(out), i + 1
		elseif char == "\\" then
			local nextChar = string.sub(text, i + 1, i + 1)
			if nextChar == "u" then
				local hex = string.match(text, "^%x%x%x%x", i + 2)
				if not hex then
					return nil, i
				end
				local code = tonumber(hex, 16) or 0
				i += 6
				if code >= 0xD800 and code <= 0xDBFF then
					local low = string.match(text, "^\\u(%x%x%x%x)", i)
					local lowCode = if low then tonumber(low, 16) else nil
					if not lowCode or lowCode < 0xDC00 or lowCode > 0xDFFF then
						return nil, i
					end
					code = 0x10000 + (code - 0xD800) * 0x400 + (lowCode - 0xDC00)
					i += 6
				elseif code >= 0xDC00 and code <= 0xDFFF then
					return nil, i
				end
				table.insert(out, utf8.char(code))
			else
				local mapped = UNESCAPES[nextChar]
				if not mapped then
					return nil, i
				end
				table.insert(out, mapped)
				i += 2
			end
		elseif string.byte(char) < 32 then
			return nil, i
		else
			table.insert(out, char)
			i += 1
		end
	end
	return nil, i
end

function Model.decodeArgv(text: string): ({ string }?, string?)
	local i = string.match(text, "^%s*()") or 1
	if string.sub(text, i, i) ~= "[" then
		return nil, ARGV_HINT
	end
	i = (string.match(text, "^%s*()", i + 1) or i + 1)
	local list: { string } = {}
	if string.sub(text, i, i) == "]" then
		i += 1
	else
		while true do
			if string.sub(text, i, i) ~= '"' then
				return nil, ARGV_HINT
			end
			local value, after = readString(text, i)
			if value == nil then
				return nil, ARGV_HINT
			end
			table.insert(list, value)
			i = string.match(text, "^%s*()", after) or after
			local separator = string.sub(text, i, i)
			i = string.match(text, "^%s*()", i + 1) or i + 1
			if separator == "]" then
				break
			elseif separator ~= "," then
				return nil, ARGV_HINT
			end
		end
	end
	if string.match(text, "^%s*$", i) == nil then
		return nil, ARGV_HINT
	end
	return list, nil
end

local function trim(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end
Model.trim = trim

function Model.triggerField(uid: number, name: string): string
	return `t{uid}-{name}`
end

local function addTrigger(draft: Draft, source: string, cron: string, event: string, filter: string): DraftTrigger
	local uid = draft.nextUid
	draft.nextUid += 1
	local trigger = { uid = uid, source = source }
	table.insert(draft.triggers, trigger)
	draft.fields[Model.triggerField(uid, "cron")] = Input.new(cron)
	draft.fields[Model.triggerField(uid, "event")] = Input.new(event)
	draft.fields[Model.triggerField(uid, "filter")] = Input.new(filter)
	return trigger
end

function Model.addTrigger(draft: Draft, source: string): DraftTrigger
	return addTrigger(draft, source, "", "", "")
end

function Model.removeTrigger(draft: Draft, uid: number)
	for index, trigger in draft.triggers do
		if trigger.uid == uid then
			table.remove(draft.triggers, index)
		end
	end
	for _, name in { "cron", "event", "filter" } do
		draft.fields[Model.triggerField(uid, name)] = nil
	end
end

local function blankDraft(): Draft
	local draft: Draft = {
		id = nil,
		revision = nil,
		enabled = true,
		agent = "omp",
		workspace = "existing",
		fields = {
			name = Input.new(""),
			instructions = Input.new("", true),
			model = Input.new(""),
			cwd = Input.new(""),
			base_branch = Input.new(""),
			command = Input.new(""),
			precheck = Input.new(""),
			precheck_timeout = Input.new(tostring(DEFAULT_PRECHECK_SECONDS)),
			grace = Input.new(tostring(DEFAULT_GRACE_MINUTES)),
		},
		triggers = {},
		nextUid = 1,
	}
	return draft
end

function Model.newDraft(): Draft
	local draft = blankDraft()
	addTrigger(draft, "schedule", "", "", "")
	return draft
end

function Model.draftFrom(definition: Definition, revision: string?): Draft
	local draft = blankDraft()
	draft.id, draft.revision, draft.enabled = definition.id, revision, definition.enabled
	draft.agent, draft.workspace = definition.agent, definition.workspace
	local fields = draft.fields
	Input.setText(fields.name, definition.name)
	Input.setText(fields.instructions, definition.instructions)
	Input.setText(fields.model, definition.model)
	Input.setText(fields.cwd, definition.cwd)
	Input.setText(fields.base_branch, definition.base_branch)
	Input.setText(fields.command, if #definition.command > 0 then Model.encodeArgv(definition.command) else "")
	local precheck = definition.precheck
	Input.setText(fields.precheck, if precheck then Model.encodeArgv(precheck.command) else "")
	Input.setText(
		fields.precheck_timeout,
		tostring(if precheck then precheck.timeout_seconds else DEFAULT_PRECHECK_SECONDS)
	)
	Input.setText(fields.grace, tostring(definition.grace_minutes))
	for _, trigger in definition.triggers do
		if trigger.kind == "schedule" then
			addTrigger(draft, "schedule", trigger.cron, "", "")
		else
			addTrigger(draft, trigger.source, "", trigger.event, trigger.filter)
		end
	end
	return draft
end

function Model.fieldOrder(draft: Draft): { string }
	local order = { "name" }
	if draft.agent ~= "command" then
		table.insert(order, "instructions")
	end
	for _, trigger in draft.triggers do
		if trigger.source == "schedule" then
			table.insert(order, Model.triggerField(trigger.uid, "cron"))
		else
			table.insert(order, Model.triggerField(trigger.uid, "event"))
			table.insert(order, Model.triggerField(trigger.uid, "filter"))
		end
	end
	if draft.workspace ~= "none" then
		table.insert(order, "cwd")
	end
	if draft.workspace == "worktree" then
		table.insert(order, "base_branch")
	end
	if draft.agent ~= "command" then
		table.insert(order, "model")
	end
	if draft.agent == "command" then
		table.insert(order, "command")
	end
	table.insert(order, "precheck")
	if trim(draft.fields.precheck.text) ~= "" then
		table.insert(order, "precheck_timeout")
	end
	table.insert(order, "grace")
	return order
end

local function wholeNumber(text: string): number?
	local digits = string.match(trim(text), "^(%d+)$")
	local value = if digits then tonumber(digits) else nil
	if value and value >= 1 then
		return value
	end
	return nil
end

export type Validation = { definition: Definition?, error: string?, focus: string? }

function Model.toDefinition(draft: Draft): Validation
	local fields = draft.fields
	local function fail(message: string, focus: string): Validation
		return { definition = nil, error = message, focus = focus }
	end
	local name = trim(fields.name.text)
	if name == "" then
		return fail("Enter a name.", "name")
	end
	local instructions = fields.instructions.text
	if draft.agent ~= "command" and trim(instructions) == "" then
		return fail("Enter instructions for the agent.", "instructions")
	end
	local triggers: { Trigger } = {}
	for _, trigger in draft.triggers do
		if trigger.source == "schedule" then
			local cron = trim(fields[Model.triggerField(trigger.uid, "cron")].text)
			if cron == "" then
				return fail("Enter a cron expression.", Model.triggerField(trigger.uid, "cron"))
			end
			table.insert(triggers, { kind = "schedule", cron = cron })
		else
			local event = trim(fields[Model.triggerField(trigger.uid, "event")].text)
			if event == "" then
				return fail("Enter the event name this trigger matches.", Model.triggerField(trigger.uid, "event"))
			end
			table.insert(triggers, {
				kind = "event",
				source = trigger.source,
				event = event,
				filter = trim(fields[Model.triggerField(trigger.uid, "filter")].text),
			})
		end
	end
	local cwd = trim(fields.cwd.text)
	if cwd == "" and draft.workspace ~= "none" then
		return fail(
			if draft.workspace == "worktree" then "Enter the repository path." else "Enter the working directory.",
			"cwd"
		)
	end
	local command: { string } = {}
	if draft.agent == "command" then
		local decoded, message = Model.decodeArgv(fields.command.text)
		if not decoded or #decoded == 0 then
			return fail(message or "Enter the program and its arguments.", "command")
		end
		command = decoded
	end
	local precheck: Precheck? = nil
	if trim(fields.precheck.text) ~= "" then
		local decoded, message = Model.decodeArgv(fields.precheck.text)
		if not decoded or #decoded == 0 then
			return fail(message or "Enter the precheck program and its arguments.", "precheck")
		end
		local seconds = tonumber(trim(fields.precheck_timeout.text))
		if seconds == nil or not (seconds > 0 and seconds < math.huge) then
			return fail("Precheck timeout must be a positive number of seconds.", "precheck_timeout")
		end
		precheck = { command = decoded, timeout_seconds = seconds }
	end
	local grace = wholeNumber(fields.grace.text)
	if not grace then
		return fail("Missed-run grace must be a whole number of minutes, at least 1.", "grace")
	end
	return {
		definition = {
			id = draft.id or "",
			name = name,
			instructions = if draft.agent == "command" then "" else instructions,
			agent = draft.agent,
			model = if draft.agent == "command" then "" else trim(fields.model.text),
			cwd = if draft.workspace == "none" then "" else cwd,
			workspace = draft.workspace,
			base_branch = if draft.workspace == "worktree" then trim(fields.base_branch.text) else "",
			command = command,
			triggers = triggers,
			precheck = precheck,
			grace_minutes = grace,
			enabled = draft.enabled,
		},
		error = nil,
		focus = nil,
	}
end

function Model.dirty(draft: Draft, baseline: Draft): boolean
	if draft.agent ~= baseline.agent or draft.workspace ~= baseline.workspace then
		return true
	end
	if #draft.triggers ~= #baseline.triggers then
		return true
	end
	for index, trigger in draft.triggers do
		local other = baseline.triggers[index]
		if trigger.uid ~= other.uid or trigger.source ~= other.source then
			return true
		end
	end
	for key, field in draft.fields do
		local other = baseline.fields[key]
		if other == nil or other.text ~= field.text then
			return true
		end
	end
	return false
end

function Model.visible(definitions: { Definition }, search: string, filter: StatusFilter): { Definition }
	local needle = string.lower(trim(search))
	local out = {}
	for _, definition in definitions do
		local matchesStatus = filter == "all" or (filter == "enabled") == definition.enabled
		if matchesStatus then
			local haystack = string.lower(definition.name .. "\n" .. definition.id)
			if needle == "" or string.find(haystack, needle, 1, true) ~= nil then
				table.insert(out, definition)
			end
		end
	end
	return out
end

function Model.find(definitions: { Definition }, id: string?): Definition?
	if id == nil then
		return nil
	end
	for _, definition in definitions do
		if definition.id == id then
			return definition
		end
	end
	return nil
end

function Model.runsOf(runs: { Run }, id: string, limit: number?): { Run }
	local out = {}
	for _, run in runs do
		if run.automationId == id then
			table.insert(out, run)
			if limit and #out >= limit then
				break
			end
		end
	end
	return out
end

export type Tone = "ok" | "bad" | "warn" | "info" | "muted"
export type Outcome = { label: string, tone: Tone }

function Model.outcome(run: Run): Outcome
	local phase = run.phase
	if phase == "exited" or phase == "completed" then
		if run.status == nil or run.status == 0 then
			return { label = "Completed", tone = "ok" }
		end
		return { label = "Failed", tone = "bad" }
	elseif phase == "failed" or phase == "launch_failed" then
		return { label = "Failed", tone = "bad" }
	elseif phase == "launched" or phase == "running" then
		return { label = "Running", tone = "info" }
	elseif phase == "claimed" or phase == "preparing" or phase == "queued" or phase == "starting" then
		return { label = "Starting", tone = "info" }
	elseif phase == "skipped_precheck" or phase == "skipped" then
		return { label = "Skipped", tone = "warn" }
	elseif phase == "interrupted" then
		return { label = "Interrupted", tone = "warn" }
	elseif phase == "missed" then
		return { label = "Missed", tone = "warn" }
	elseif phase == "uncertain" or phase == "unknown" then
		return { label = "Unknown", tone = "warn" }
	end
	return { label = phase, tone = "muted" }
end

function Model.triggerLabel(trigger: string): string
	if trigger == "scheduled" or trigger == "schedule" then
		return "Schedule"
	elseif trigger == "manual" then
		return "Manual"
	end
	local source = string.match(trigger, "^event:([^:]*):")
	if source ~= nil then
		return `{Model.label(Model.SOURCES, source)} event`
	end
	return Model.label(Model.SOURCES, trigger)
end

export type TriggerLine = { kind: string, detail: string }

function Model.triggerLines(definition: Definition): { TriggerLine }
	local lines = {}
	for _, trigger in definition.triggers do
		if trigger.kind == "schedule" then
			table.insert(lines, { kind = "Schedule", detail = trigger.cron })
		else
			local detail = trigger.event
			if trigger.filter ~= "" then
				detail ..= ` · {trigger.filter}`
			end
			table.insert(lines, { kind = `{Model.label(Model.SOURCES, trigger.source)} event`, detail = detail })
		end
	end
	if #lines == 0 then
		table.insert(lines, { kind = "Manual", detail = "Run now only" })
	end
	return lines
end

local function format(pattern: string, at: number): string
	local text = os.date(pattern, at)
	return if type(text) == "string" then text else ""
end

local function dayNumber(at: number): number
	local parts = os.date("*t", at)
	if type(parts) ~= "table" then
		return 0
	end
	return math.floor(os.time({ year = parts.year, month = parts.month, day = parts.day, hour = 12 }) / 86400)
end

local function plural(count: number, unit: string): string
	return `{count} {unit}{if count == 1 then "" else "s"}`
end

function Model.when(at: number, now: number): string
	local days = dayNumber(at) - dayNumber(now)
	local clock = format("%H:%M", at)
	if days == 0 then
		return `Today, {clock}`
	elseif days == 1 then
		return `Tomorrow, {clock}`
	elseif days == -1 then
		return `Yesterday, {clock}`
	elseif days > 1 and days < 7 then
		return `{format("%a", at)}, {clock}`
	end
	return `{format("%b %d", at)}, {clock}`
end

function Model.ago(at: number, now: number): string
	local seconds = now - at
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{plural(seconds // 60, "minute")} ago`
	elseif seconds < 86400 then
		return `{plural(seconds // 3600, "hour")} ago`
	end
	return `{plural(seconds // 86400, "day")} ago`
end

function Model.nextRun(definition: Definition, snapshot: Snapshot, now: number): (string, string?)
	if not definition.enabled then
		return "Paused", nil
	end
	local at = snapshot.nextRuns[definition.id]
	if at ~= nil then
		return Model.when(at, now), nil
	end
	for _, trigger in definition.triggers do
		if trigger.kind == "event" then
			return "On event", nil
		end
	end
	return "Manual only", nil
end

Model.EVENT_NOTE =
	"Events start a run only when the authenticated local receiver delivers them. Nothing is subscribed for you."

Model.PERMISSION_NOTE =
	"The selected agent runs with its own tool and account permissions. This editor does not grant, limit, or store credentials."

function Model.healthLabel(health: string): string
	if health == "ok" then
		return "Scheduler running"
	elseif health == "degraded" then
		return "Scheduler degraded"
	elseif health == "stopped" then
		return "Scheduler stopped"
	end
	return health
end

return Model
