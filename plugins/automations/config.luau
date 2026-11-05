--!strict
local canon = require("./canon")
local events = require("./events")
local jsonSource = require("./json-source")
local raw = require("./raw")
local schedule = require("./schedule")


export type ScheduleTrigger = { kind: "schedule", cron: string }
export type EventTrigger = { kind: "event", source: string, event: string, filter: string }
export type Trigger = ScheduleTrigger | EventTrigger
export type Precheck = { command: { string }, timeout_seconds: number }

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

export type EventRule = { source: string, event: string, terms: { events.Term } }

-- A validated definition with its triggers parsed.
export type Automation = {
	def: Definition,
	crons: { schedule.Cron },
	rules: { EventRule },
}

type EntrySource = { range: jsonSource.Range, members: { jsonSource.Member } }
type DocumentSource = {
	text: string,
	root: jsonSource.Range,
	members: { jsonSource.Member },
	automations: jsonSource.Range?,
}

export type Entry = {
	value: unknown,
	def: Definition?,
	problem: string?,
	revision: string,
	source: EntrySource?,
	change: ("definition" | "enabled")?,
}

export type Document = {
	top: raw.Object,
	entries: { Entry },
	-- Problems to show; an entry's own problem is repeated here.
	errors: { string },
	exists: boolean,
	-- Set when the file cannot be safely rewritten (not JSON, or the wrong shape).
	unsaveable: string?,
	source: DocumentSource?,
}

local DEFAULT_GRACE_MINUTES = 60
local DEFAULT_PRECHECK_SECONDS = 60
local MAX_INSTRUCTIONS = 64 * 1024
local MAX_TRIGGERS = 8

local AGENTS = { command = true, omp = true, codex = true, claude = true }
local WORKSPACES = { existing = true, none = true, worktree = true }

local KNOWN = {
	id = true,
	name = true,
	instructions = true,
	agent = true,
	model = true,
	cwd = true,
	workspace = true,
	base_branch = true,
	command = true,
	cron = true,
	triggers = true,
	precheck = true,
	grace_minutes = true,
	enabled = true,
}

local KEY_ORDER = {
	"id",
	"name",
	"agent",
	"model",
	"instructions",
	"workspace",
	"cwd",
	"base_branch",
	"command",
	"cron",
	"triggers",
	"kind",
	"source",
	"event",
	"filter",
	"precheck",
	"timeout_seconds",
	"grace_minutes",
	"enabled",
}

local EMPTY_ARRAY: { unknown } = table.freeze({})

local function expand(path: string, home: string): string
	if path == "~" then
		return home
	end
	local rest = string.match(path, "^~/(.*)$")
	return if rest then `{home}/{rest}` else path
end

local function expandAll(args: { string }, home: string): { string }
	local out: { string } = {}
	for _, arg in args do
		table.insert(out, expand(arg, home))
	end
	return out
end

local function validId(id: string): boolean
	return string.match(id, "^[a-z0-9][a-z0-9-]*$") ~= nil
end

local function validArgv(args: { string }): boolean
	if #args == 0 or args[1] == "" then
		return false
	end
	for _, arg in args do
		if string.find(arg, "\0", 1, true) then
			return false
		end
	end
	return true
end

local function validCwd(cwd: string): boolean
	if string.match(cwd, "^%s") ~= nil or string.match(cwd, "%s$") ~= nil then
		return false
	end
	return cwd == "~" or string.sub(cwd, 1, 1) == "/" or string.sub(cwd, 1, 2) == "~/"
end

local function validRef(ref: string): boolean
	return #ref <= 200 and string.match(ref, "^[A-Za-z0-9][A-Za-z0-9._/@+-]*$") ~= nil and not string.find(ref, "..", 1, true)
end

local function validModel(model: string): boolean
	return #model <= 128 and string.match(model, "^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$") ~= nil
end

local function compile(def: Definition): (Automation?, string?)
	if not validId(def.id) then
		return nil, "id must be lowercase letters, digits and - (starting with a letter or digit)"
	end
	if def.name == "" or utf8.len(def.name) == nil or string.find(def.name, "%c") then
		return nil, "name is required, valid Unicode, one line"
	end
	if not AGENTS[def.agent] then
		return nil, "agent must be command, omp, codex or claude"
	end
	if not WORKSPACES[def.workspace] then
		return nil, "workspace must be existing, none or worktree"
	end
	if def.agent == "command" then
		if not validArgv(def.command) then
			return nil, "command must be a non-empty list of arguments with a non-empty program and no NUL bytes"
		end
		if def.instructions ~= "" then
			return nil, "instructions apply to omp, codex and claude agents; the command agent runs its command as given"
		end
		if def.model ~= "" then
			return nil, "model applies to omp, codex and claude agents"
		end
	else
		if #def.command > 0 then
			return nil, "command applies only to the command agent"
		end
		if string.match(def.instructions, "%S") == nil then
			return nil, "instructions are required for this agent"
		end
		if #def.instructions > MAX_INSTRUCTIONS or string.find(def.instructions, "\0", 1, true) then
			return nil, "instructions must be text of at most 64 KiB"
		end
		if def.model ~= "" and not validModel(def.model) then
			return nil, "model must be a model name (letters, digits and . _ : / @ + -)"
		end
	end
	if def.workspace == "none" then
		if def.cwd ~= "" then
			return nil, "workspace none runs in an empty scratch folder; leave cwd blank"
		end
	elseif not validCwd(def.cwd) then
		return nil, "cwd must be an absolute or ~/ path"
	end
	if def.workspace == "worktree" then
		if def.base_branch ~= "" and not validRef(def.base_branch) then
			return nil, "base_branch must be a branch, tag or commit name"
		end
	elseif def.base_branch ~= "" then
		return nil, "base_branch applies to workspace worktree"
	end
	local precheck = def.precheck
	if precheck then
		if not validArgv(precheck.command) then
			return nil, "precheck.command must be a non-empty list of arguments with a non-empty program and no NUL bytes"
		end
		if not (precheck.timeout_seconds > 0 and precheck.timeout_seconds < math.huge) then
			return nil, "precheck.timeout_seconds must be a positive finite number"
		end
	end
	if not (def.grace_minutes >= 1 and def.grace_minutes < math.huge) then
		return nil, "grace_minutes must be a finite number of at least 1"
	end
	if #def.triggers > MAX_TRIGGERS then
		return nil, "at most 8 triggers"
	end
	local crons: { schedule.Cron } = {}
	local rules: { EventRule } = {}
	for i, trigger in def.triggers do
		if trigger.kind == "schedule" then
			local cron, err = schedule.parse(trigger.cron)
			if not cron then
				return nil, `trigger {i}: {err}`
			end
			table.insert(crons, cron)
		elseif trigger.kind == "event" then
			if not events.isSource(trigger.source) then
				return nil, `trigger {i}: source must be github, webhook, slack or linear`
			end
			if trigger.event ~= "*" and not events.validEventName(trigger.event) then
				return nil, `trigger {i}: event must be an event name or *`
			end
			local terms, err = events.parseFilter(trigger.filter)
			if not terms then
				return nil, `trigger {i}: {err}`
			end
			table.insert(rules, { source = trigger.source, event = trigger.event, terms = terms })
		else
			return nil, `trigger {i}: kind must be schedule or event`
		end
	end
	return { def = def, crons = crons, rules = rules }, nil
end

local function triggersOf(doc: raw.Object): ({ Trigger }?, string?)
	if doc.cron ~= nil and doc.triggers ~= nil then
		return nil, "use either cron or triggers, not both"
	end
	if doc.triggers == nil then
		if type(doc.cron) ~= "string" then
			return nil, "cron is required (or triggers)"
		end
		return { { kind = "schedule", cron = doc.cron } }, nil
	end
	local items = raw.array(doc.triggers)
	if not items then
		return nil, "triggers must be an array"
	end
	local out: { Trigger } = {}
	for i, item in items do
		local trigger = raw.object(item)
		if not trigger then
			return nil, `trigger {i} is not an object`
		end
		if trigger.kind == "schedule" and type(trigger.cron) == "string" then
			table.insert(out, { kind = "schedule", cron = trigger.cron })
		elseif trigger.kind == "event" and type(trigger.source) == "string" and type(trigger.event) == "string" then
			local filter = trigger.filter
			if filter ~= nil and type(filter) ~= "string" then
				return nil, `trigger {i}: filter must be a string`
			end
			table.insert(out, { kind = "event", source = trigger.source, event = trigger.event, filter = filter or "" })
		else
			return nil, `trigger {i} needs kind schedule with cron, or kind event with source and event`
		end
	end
	return out, nil
end

local function fromEntry(value: unknown): (Definition?, string?)
	local doc = raw.object(value)
	if not doc then
		return nil, "entry is not an object"
	end
	local id = doc.id
	if type(id) ~= "string" or not validId(id) then
		return nil, `id {tostring(id)} must match [a-z0-9][a-z0-9-]*`
	end
	local problem: string? = nil
	local function str(key: string, default: string): string
		local item = doc[key]
		if item == nil then
			return default
		end
		if type(item) ~= "string" then
			problem = problem or `{key} must be a string`
			return default
		end
		return item
	end
	local name = str("name", id)
	local instructions = str("instructions", "")
	local agent = str("agent", "command")
	local model = str("model", "")
	local cwd = str("cwd", "")
	local workspace = str("workspace", "existing")
	local base = str("base_branch", "")
	local command: { string } = {}
	if doc.command ~= nil then
		local given = raw.strings(doc.command)
		if given then
			command = given
		else
			problem = problem or "command must be an array of strings"
		end
	end
	local triggers, triggerErr = triggersOf(doc)
	local precheck: Precheck? = nil
	if doc.precheck ~= nil then
		local given = raw.object(doc.precheck)
		local pre = if given then raw.strings(given.command) else nil
		local seconds = if given then given.timeout_seconds else nil
		if seconds == nil then
			seconds = DEFAULT_PRECHECK_SECONDS
		end
		if pre and type(seconds) == "number" then
			precheck = { command = pre, timeout_seconds = seconds }
		else
			problem = problem or "precheck needs command (array of strings) and a numeric timeout_seconds"
		end
	end
	local grace = doc.grace_minutes
	if grace == nil then
		grace = DEFAULT_GRACE_MINUTES
	end
	if type(grace) ~= "number" or grace < 1 then
		problem = problem or "grace_minutes must be at least 1"
		grace = DEFAULT_GRACE_MINUTES
	end
	local enabled = doc.enabled
	if enabled == nil then
		enabled = true
	end
	if type(enabled) ~= "boolean" then
		problem = problem or "enabled must be true or false"
		enabled = true
	end
	if not triggers then
		problem = problem or triggerErr or "invalid triggers"
	end
	if problem or not triggers then
		return nil, `{id}: {problem}`
	end
	local def: Definition = {
		id = id,
		name = name,
		instructions = instructions,
		agent = agent,
		model = model,
		cwd = cwd,
		workspace = workspace,
		base_branch = base,
		command = command,
		triggers = triggers,
		precheck = precheck,
		grace_minutes = math.floor(grace),
		enabled = enabled,
	}
	local automation, invalid = compile(def)
	if not automation then
		return nil, `{id}: {invalid}`
	end
	return def, nil
end

local function parseDocument(text: string?, decode: (string) -> unknown): Document
	local doc: Document = { top = {}, entries = {}, errors = {}, exists = text ~= nil, unsaveable = nil }
	if text == nil then
		return doc
	end
	local ok, decoded = pcall(decode, text)
	if not ok then
		doc.unsaveable = "the config file is not valid JSON; fix or remove it first"
		table.insert(doc.errors, doc.unsaveable)
		return doc
	end
	local root = jsonSource.range(text, 1)
	local top = raw.object(decoded)
	if not top or string.byte(text, root.first) ~= 123 then
		doc.unsaveable = "the config file must be a JSON object with an `automations` array"
		table.insert(doc.errors, doc.unsaveable)
		return doc
	end
	doc.top = top
	local members = jsonSource.members(text, root, decode)
	local arrayRange: jsonSource.Range? = nil
	for _, member in members do
		if member.key == "automations" then
			arrayRange = member.value
		end
	end
	doc.source = { text = text, root = root, members = members, automations = arrayRange }
	if not arrayRange then
		table.insert(doc.errors, "config needs an `automations` array")
		return doc
	end
	local items = raw.array(top.automations)
	if not items or string.byte(text, arrayRange.first) ~= 91 then
		doc.unsaveable = "`automations` in the config file must be an array"
		table.insert(doc.errors, doc.unsaveable)
		return doc
	end
	local seen: { [string]: boolean } = {}
	for i, range in jsonSource.items(text, arrayRange) do
		local item = items[i]
		local def, problem = fromEntry(item)
		if def and seen[def.id] then
			def, problem = nil, `{def.id}: duplicate id`
		end
		if def then
			seen[def.id] = true
		elseif problem then
			table.insert(doc.errors, problem)
		end
		table.insert(doc.entries, {
			value = item,
			def = def,
			problem = problem,
			revision = jsonSource.slice(text, range),
			source = { range = range, members = if def then jsonSource.members(text, range, decode) else {} },
		})
	end
	return doc
end

local function definitions(doc: Document): { Definition }
	local out: { Definition } = {}
	for _, entry in doc.entries do
		if entry.def then
			table.insert(out, entry.def)
		end
	end
	return out
end

local function leafOf(host: canon.Encoder): canon.Encoder
	return function(value: unknown, pretty: boolean?): string
		if value == EMPTY_ARRAY then
			return "[]"
		end
		return host(value, pretty)
	end
end


local function copy(items: { string }): { unknown }
	local out: { unknown } = {}
	for _, item in items do
		table.insert(out, item)
	end
	return if #out == 0 then EMPTY_ARRAY else out
end

local function toEntry(def: Definition, original: unknown): raw.Object
	local out: raw.Object = {}
	local previous = raw.object(original)
	if previous then
		for key, value in previous do
			if not KNOWN[key] then
				out[key] = value
			end
		end
	end
	out.id = def.id
	out.name = def.name
	out.agent = def.agent
	out.workspace = def.workspace
	if def.instructions ~= "" then
		out.instructions = def.instructions
	end
	if def.model ~= "" then
		out.model = def.model
	end
	if def.cwd ~= "" then
		out.cwd = def.cwd
	end
	if def.base_branch ~= "" then
		out.base_branch = def.base_branch
	end
	if #def.command > 0 then
		out.command = copy(def.command)
	end
	local only = def.triggers[1]
	if #def.triggers == 1 and only and only.kind == "schedule" then
		out.cron = only.cron
	else
		local list: { unknown } = {}
		for _, trigger in def.triggers do
			if trigger.kind == "schedule" then
				table.insert(list, { kind = "schedule", cron = trigger.cron })
			else
				local item: raw.Object = { kind = "event", source = trigger.source, event = trigger.event }
				if trigger.filter ~= "" then
					item.filter = trigger.filter
				end
				table.insert(list, item)
			end
		end
		out.triggers = if #list == 0 then EMPTY_ARRAY else list
	end
	local precheck = def.precheck
	if precheck then
		out.precheck = { command = copy(precheck.command), timeout_seconds = precheck.timeout_seconds }
	end
	out.grace_minutes = def.grace_minutes
	out.enabled = def.enabled
	return out
end

local function encodeEntry(entry: Entry, text: string, leaf: canon.Encoder): string
	local source = entry.source
	if not source then
		return canon.encode(leaf, KEY_ORDER, entry.value, true)
	end
	if not entry.change then
		return jsonSource.slice(text, source.range)
	end
	local def = entry.def
	assert(def, "only valid definitions can be changed")
	local members: { string } = {}
	for _, member in source.members do
		if (entry.change == "definition" and not KNOWN[member.key]) or (entry.change == "enabled" and member.key ~= "enabled") then
			table.insert(members, jsonSource.slice(text, member.range))
		end
	end
	if entry.change == "enabled" then
		table.insert(members, '"enabled": ' .. leaf(def.enabled, false))
		return "{\n\t" .. table.concat(members, ",\n\t") .. "\n}"
	end
	local known = canon.encode(leaf, KEY_ORDER, toEntry(def, nil), true)
	if #members == 0 then
		return known
	end
	return string.sub(known, 1, #known - 2) .. ",\n\t" .. table.concat(members, ",\n\t") .. "\n}"
end

local function encodeDocument(doc: Document, leaf: canon.Encoder): string
	local source = doc.source
	if not source then
		local top: raw.Object = {}
		for key, value in doc.top do
			top[key] = value
		end
		local items: { unknown } = {}
		for _, entry in doc.entries do
			table.insert(items, entry.value)
		end
		top.automations = if #items == 0 then EMPTY_ARRAY else items
		return canon.encode(leaf, KEY_ORDER, top, true) .. "\n"
	end
	local items: { string } = {}
	for _, entry in doc.entries do
		table.insert(items, encodeEntry(entry, source.text, leaf))
	end
	local array = if #items == 0 then "[]" else "[\n\t" .. table.concat(items, ",\n\t") .. "\n]"
	local range = source.automations
	if range then
		return string.sub(source.text, 1, range.first - 1) .. array .. string.sub(source.text, range.last + 1)
	end
	local comma = if #source.members == 0 then "" else ","
	return string.sub(source.text, 1, source.root.last - 1)
		.. comma .. '\n\t"automations": ' .. array .. "\n"
		.. string.sub(source.text, source.root.last)
end

local function entryId(entry: Entry): unknown
	local def = entry.def
	if def then
		return def.id
	end
	local value = raw.object(entry.value)
	return if value then value.id else nil
end

local function findEntry(doc: Document, id: string): (Entry?, number?)
	for i, entry in doc.entries do
		local def = entry.def
		if def and def.id == id then
			return entry, i
		end
	end
	return nil, nil
end

local function slug(name: string, taken: (string) -> boolean): string
	local base = string.lower(name)
	base = string.gsub(base, "[^a-z0-9]+", "-")
	base = string.gsub(base, "^%-+", "")
	base = string.sub(base, 1, 40)
	base = string.gsub(base, "%-+$", "")
	if base == "" then
		base = "automation"
	end
	if not taken(base) then
		return base
	end
	local n = 2
	while taken(`{base}-{n}`) do
		n += 1
	end
	return `{base}-{n}`
end

local function idTaken(doc: Document, id: string): boolean
	for _, entry in doc.entries do
		if entryId(entry) == id then
			return true
		end
	end
	return false
end

local CONFLICT = "the automation changed on disk since you opened it; reopen it to see the current version"

-- Applies a candidate to the document. `expected` is the revision the edit started from;
-- nil means a new automation. Returns the saved id.
local function upsert(doc: Document, candidate: Definition, expected: string?): (string?, string?)
	if doc.unsaveable then
		return nil, doc.unsaveable
	end
	local def: Definition = table.clone(candidate)
	if expected == nil then
		if def.id == "" then
			def.id = slug(def.name, function(id)
				return idTaken(doc, id)
			end)
		elseif idTaken(doc, def.id) then
			return nil, `an automation with id {def.id} already exists`
		end
		local automation, err = compile(def)
		if not automation then
			return nil, err
		end
		table.insert(doc.entries, { value = toEntry(def, nil), def = def, problem = nil, revision = "" })
		return def.id, nil
	end
	local entry, index = findEntry(doc, def.id)
	if def.id == "" or not entry or not index then
		return nil, if def.id == "" then "id is required to edit an automation" else CONFLICT
	end
	if entry.revision ~= expected then
		return nil, CONFLICT
	end
	local automation, err = compile(def)
	if not automation then
		return nil, err
	end
	doc.entries[index] = {
		value = toEntry(def, entry.value),
		def = def,
		problem = nil,
		revision = "",
		source = entry.source,
		change = "definition",
	}
	return def.id, nil
end

local function toggle(doc: Document, id: string, enabled: boolean, expected: string?): (boolean, string?)
	if doc.unsaveable then
		return false, doc.unsaveable
	end
	local entry, index = findEntry(doc, id)
	if not entry or not index then
		return false, CONFLICT
	end
	if expected ~= nil and entry.revision ~= expected then
		return false, CONFLICT
	end
	local def = entry.def
	local value = raw.object(entry.value)
	if not def or not value then
		return false, `{id} has a problem to fix first: {entry.problem}`
	end
	local changed: Definition = table.clone(def)
	changed.enabled = enabled
	value.enabled = enabled
	doc.entries[index] = {
		value = value,
		def = changed,
		problem = nil,
		revision = "",
		source = entry.source,
		change = if entry.change == "definition" then "definition" else "enabled",
	}
	return true, nil
end

return {
	EMPTY_ARRAY = EMPTY_ARRAY,
	expand = expand,
	expandAll = expandAll,
	compile = compile,
	parseDocument = parseDocument,
	definitions = definitions,
	encodeDocument = encodeDocument,
	leafOf = leafOf,
	findEntry = findEntry,
	upsert = upsert,
	toggle = toggle,
}
