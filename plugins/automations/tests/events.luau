--!strict
local events = require("../events")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL events: " .. name)
	end
end

local function event(over: { [string]: unknown }?): events.Event
	local doc: { [string]: unknown } = {
		id = "delivery-1",
		source = "github",
		event = "pull_request",
		received_at = 100,
		attributes = { repo = "example-org/example-repo", label = "ready" },
	}
	for k, v in over or {} do
		doc[k] = v
	end
	local ev, err = events.parse(doc)
	assert(ev, err)
	return ev
end

local ev = event()
local function matches(name: string, filter: string): boolean
	local terms, err = events.parseFilter(filter)
	assert(terms, err)
	return events.matches(name, terms, ev)
end

check("blank filter matches the named event", matches("pull_request", ""))
check("another event name does not match", not matches("push", ""))
check("* matches any event name", matches("*", ""))
check("every term must match", matches("pull_request", "repo=example-org/example-repo label=ready") and not matches("pull_request", "repo=example-org/example-repo label=draft"))
check("a trailing * matches by prefix", matches("pull_request", "repo=example-org/*"))
check("a missing attribute never matches", not matches("pull_request", "branch=main"))
check("a malformed term is an error", events.parseFilter("nonsense") == nil)

check("unknown fields are refused", events.parse({ id = "a", source = "github", event = "x", received_at = 1, surprise = true }) == nil)
check("an unknown source is refused", events.parse({ id = "a", source = "email", event = "x", received_at = 1 }) == nil)
check("an id with spaces is refused", events.parse({ id = "a b", source = "slack", event = "x", received_at = 1 }) == nil)
check("attribute values must be strings", events.parse({ id = "a", source = "slack", event = "x", received_at = 1, attributes = { n = 1 } }) == nil)
check("received_at is required", events.parse({ id = "a", source = "slack", event = "x" }) == nil)

check("the key separates ids and sources", events.key("github", "delivery-1") ~= events.key("github", "delivery-2") and events.key("github", "x") ~= events.key("linear", "x"))

if failures > 0 then
	error(failures .. " event checks failed")
end
return true
