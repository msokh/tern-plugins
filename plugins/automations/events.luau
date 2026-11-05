--!strict
local raw = require("./raw")

-- Normalized events: the one shape the inbox holds, whatever bridge delivered it.
--   { id, source, event, at?, attributes?, payload?, received_at }
-- `received_at` is stamped by the receiver (epoch seconds); everything else comes from the sender.
-- A trigger's filter compares against `attributes` only; `payload` is passed to the agent as
-- untrusted context and never interpreted here.

export type Source = "github" | "webhook" | "slack" | "linear"

export type Event = {
	id: string,
	source: Source,
	event: string,
	receivedAt: number,
	at: number?,
	attributes: { [string]: string },
	payload: unknown,
}

export type Term = { key: string, value: string, prefix: boolean }

local SOURCES: { [string]: Source } = {
	github = "github",
	webhook = "webhook",
	slack = "slack",
	linear = "linear",
}

local MAX_ATTRIBUTES = 32
local MAX_ATTRIBUTE_VALUE = 256

local function isSource(value: unknown): Source?
	return if type(value) == "string" then SOURCES[value] else nil
end

local function validId(value: string): boolean
	return #value >= 1 and #value <= 128 and string.match(value, "^[A-Za-z0-9._:-]+$") ~= nil
end

local function validEventName(value: string): boolean
	return #value >= 1 and #value <= 128 and string.match(value, "^[A-Za-z0-9._:/-]+$") ~= nil
end

local function validAttributeKey(value: string): boolean
	return #value >= 1 and #value <= 64 and string.match(value, "^[A-Za-z0-9_.-]+$") ~= nil
end

-- Filter text: space-separated `key=value` terms, all of which must match. A value ending in `*`
-- matches by prefix. Blank text matches every event.
local function parseFilter(text: string): ({ Term }?, string?)
	local terms: { Term } = {}
	for word in string.gmatch(text, "%S+") do
		local key, value = string.match(word, "^([^=]+)=(.+)$")
		if not key or not value or not validAttributeKey(key) then
			return nil, `filter term "{word}" must look like key=value`
		end
		if string.find(value, "[%c\127]") or string.find(value, "\194[\128-\159]") or string.find(value, "\226\128[\168\169]") then
			return nil, `filter term "{key}" has a control character in its value`
		end
		local prefix = string.sub(value, -1) == "*"
		table.insert(terms, { key = key, value = if prefix then string.sub(value, 1, -2) else value, prefix = prefix })
	end
	if #terms > 8 then
		return nil, "filter takes at most 8 terms"
	end
	return terms, nil
end

local function matches(eventName: string, terms: { Term }, ev: Event): boolean
	if eventName ~= "*" and eventName ~= ev.event then
		return false
	end
	for _, term in terms do
		local actual = ev.attributes[term.key]
		if actual == nil then
			return false
		end
		if term.prefix then
			if string.sub(actual, 1, #term.value) ~= term.value then
				return false
			end
		elseif actual ~= term.value then
			return false
		end
	end
	return true
end

local ALLOWED = { id = true, source = true, event = true, at = true, attributes = true, payload = true, received_at = true }

local function parse(value: unknown): (Event?, string?)
	local doc = raw.object(value)
	if not doc then
		return nil, "event is not an object"
	end
	for key in doc do
		if not ALLOWED[key] then
			return nil, `unknown field {key}`
		end
	end
	local id = doc.id
	if type(id) ~= "string" or not validId(id) then
		return nil, "id must be 1-128 characters of A-Z a-z 0-9 . _ : -"
	end
	local source = isSource(doc.source)
	if not source then
		return nil, "source must be github, webhook, slack or linear"
	end
	local name = doc.event
	if type(name) ~= "string" or not validEventName(name) then
		return nil, "event must be 1-128 characters of A-Z a-z 0-9 . _ : / -"
	end
	local at = doc.at
	if at ~= nil and (type(at) ~= "number" or at < 0 or at ~= math.floor(at)) then
		return nil, "at must be whole epoch seconds"
	end
	local received = doc.received_at
	if type(received) ~= "number" or received < 0 then
		return nil, "received_at is missing"
	end
	local attributes: { [string]: string } = {}
	if doc.attributes ~= nil then
		local given = raw.object(doc.attributes)
		if not given then
			return nil, "attributes must be an object"
		end
		local count = 0
		for key, item in given do
			count += 1
			if count > MAX_ATTRIBUTES or not validAttributeKey(key) then
				return nil, "attributes take at most 32 keys of A-Z a-z 0-9 _ . -"
			end
			if type(item) ~= "string" or #item > MAX_ATTRIBUTE_VALUE then
				return nil, "attribute values must be strings of at most 256 bytes"
			end
			attributes[key] = item
		end
	end
	return {
		id = id,
		source = source,
		event = name,
		receivedAt = received,
		at = if type(at) == "number" then at else nil,
		attributes = attributes,
		payload = doc.payload,
	}, nil
end

local function fnv(text: string, seed: number): number
	local h = seed
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- Why: h * 16777619 would pass 2^53; 16777619 = 2^24 + 403 keeps every step exact.
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

-- A stable 16-hex key for one delivery of one source's event; names its runs and its dedupe slot.
local function key(source: Source, id: string): string
	local text = `{source}:{id}`
	return string.format("%08x%08x", fnv(text, 2166136261), fnv(text, 3323198485))
end

return {
	isSource = isSource,
	validEventName = validEventName,
	parseFilter = parseFilter,
	matches = matches,
	parse = parse,
	key = key,
}
