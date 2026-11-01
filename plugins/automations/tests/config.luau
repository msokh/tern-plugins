--!strict
local config = require("../config")
local support = require("./support")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL config: " .. name)
	end
end

local leaf = support.encodeLeaf

local function parse(text: string): config.Document
	return config.parseDocument(text, support.decode)
end

local function definition(): config.Definition
	return {
		id = "daily-review",
		name = "Daily review",
		instructions = "",
		agent = "command",
		model = "",
		cwd = "~/automations/daily-review",
		workspace = "existing",
		base_branch = "",
		command = { "omp", "-p", "@prompt.md" },
		triggers = { { kind = "schedule", cron = "35 9 * * *" } },
		precheck = nil,
		grace_minutes = 60,
		enabled = true,
	}
end

local legacy = parse([[{"automations":[
	{"id":"daily-review","cron":"35 9 * * *","cwd":"~/automations/daily-review","command":["omp","-p","@prompt.md"],"precheck":{"command":["~/bin/check"]},"enabled":false},
	{"id":"Bad Id","cron":"* * * * *","cwd":"/tmp","command":["true"]},
	{"id":"daily-review","cron":"0 * * * *","cwd":"/tmp","command":["true"]},
	{"id":"relative","cron":"0 * * * *","cwd":"work","command":["true"]},
	{"id":"both","cron":"0 * * * *","triggers":[],"cwd":"/tmp","command":["true"]}
]}]])
check("a valid legacy entry loads", #config.definitions(legacy) == 1)
check("bad id, duplicate id, relative cwd and cron+triggers are all reported", #legacy.errors == 4)
check("every entry stays in the document, valid or not", #legacy.entries == 5)
local first = config.definitions(legacy)[1]
check("a legacy cron becomes a schedule trigger", first.triggers[1].kind == "schedule")
check("~ expands only on request", config.expand("~/x", "/h") == "/h/x" and first.cwd == "~/automations/daily-review")
check("a missing automations array is reported", #parse("{}").errors == 1 and parse("{}").unsaveable == nil)
check("a non-JSON file cannot be saved over", parse("{ nope").unsaveable ~= nil)

local emptyArg = parse([[{"automations":[{"id":"replace","cron":"* * * * *","cwd":"/tmp","command":["sed","-i","","s/a/b/","f"]}]}]])
local emptyArgDef = config.definitions(emptyArg)[1]
check("an empty argument after the program loads in its original position", emptyArgDef ~= nil and #emptyArgDef.command == 5 and emptyArgDef.command[3] == "")
if emptyArgDef then
	local expanded = config.expandAll(emptyArgDef.command, "/example-home")
	check("argument expansion preserves the empty argv item", #expanded == 5 and expanded[3] == "" and expanded[4] == "s/a/b/")
	local saved, problem = config.upsert(emptyArg, emptyArgDef, emptyArg.entries[1].revision)
	local reloaded = config.definitions(parse(config.encodeDocument(emptyArg, config.leafOf(leaf))))[1]
	check("editing preserves an empty command argument", saved == "replace" and problem == nil and reloaded ~= nil and #reloaded.command == 5 and reloaded.command[3] == "")
end

local longId = string.rep("a", 100)
local longArg = string.rep("x", 4097)
local unbounded = parse('{"automations":[{"id":"' .. longId .. '","cron":"* * * * *","cwd":"/tmp","command":["echo","' .. longArg .. '"],"precheck":{"command":["test","","' .. longArg .. '"],"timeout_seconds":7200},"grace_minutes":43200}]}')
local unboundedDef = config.definitions(unbounded)[1]
check("a long existing id and its default display name load without truncation", unboundedDef ~= nil and unboundedDef.id == longId and unboundedDef.name == longId)
check("an existing argument longer than 4096 bytes loads unchanged", unboundedDef ~= nil and unboundedDef.command[2] == longArg)
check("a long precheck timeout and empty precheck argument load", unboundedDef ~= nil and unboundedDef.precheck ~= nil and unboundedDef.precheck.timeout_seconds == 7200 and unboundedDef.precheck.command[2] == "" and unboundedDef.precheck.command[3] == longArg)
check("an existing grace longer than seven days loads", unboundedDef ~= nil and unboundedDef.grace_minutes == 43200)
if unboundedDef then
	local saved, problem = config.upsert(unbounded, unboundedDef, unbounded.entries[1].revision)
	local reloaded = config.definitions(parse(config.encodeDocument(unbounded, config.leafOf(leaf))))[1]
	check("editing keeps the full id, default name, long argv, timeout and grace", saved == longId and problem == nil and reloaded ~= nil and reloaded.id == longId and reloaded.name == longId and reloaded.command[2] == longArg and reloaded.precheck ~= nil and reloaded.precheck.timeout_seconds == 7200 and reloaded.grace_minutes == 43200)
	local creating = parse([[{"automations":[]}]])
	local createdId, createProblem = config.upsert(creating, unboundedDef, nil)
	check("new saves use the same unrestricted id, argv, timeout and grace validation", createdId == longId and createProblem == nil)
end

local malformedName = parse([[{"automations":[{"id":"named","name":12,"cron":"* * * * *","cwd":"/tmp","command":["true"]}]}]])
check("a non-string external name remains invalid and preserved", #config.definitions(malformedName) == 0 and #malformedName.errors == 1 and #malformedName.entries == 1)

local fractional = config.definitions(parse([[{"automations":[{"id":"fractional","cron":"* * * * *","cwd":"/tmp","command":["true"],"precheck":{"command":["true"],"timeout_seconds":0.5},"grace_minutes":1.5}]}]]))[1]
check("a positive subsecond precheck timeout loads", fractional ~= nil and fractional.precheck ~= nil and fractional.precheck.timeout_seconds == 0.5)
check("fractional legacy grace retains whole-minute scheduling semantics", fractional ~= nil and fractional.grace_minutes == 1)

local doc = parse([[{"extra":{"keep":1},"automations":[{"id":"a","cron":"* * * * *","cwd":"/tmp","command":["true"],"note":"mine"}]}]])
local ok, err = config.toggle(doc, "a", false, doc.entries[1].revision)
local text = config.encodeDocument(doc, config.leafOf(leaf))
local toggled = config.definitions(parse(text))[1]
check("toggle succeeds and keeps unknown keys", ok and err == nil and string.find(text, "mine", 1, true) ~= nil and string.find(text, '"keep"', 1, true) ~= nil)
check("toggle persists the changed flag without adding unrelated fields", toggled ~= nil and not toggled.enabled and string.find(text, '"agent"', 1, true) == nil)
local stale, staleErr = config.toggle(doc, "a", true, "old revision")
check("a stale revision is a conflict", not stale and staleErr ~= nil)

local fresh = parse([[{"automations":[]}]])
local id = config.upsert(fresh, definition(), nil)
check("new definition is accepted", id == "daily-review")
local manual = definition()
manual.id = "manual-only"
manual.triggers = {}
config.upsert(fresh, manual, nil)
check("a manual-only automation encodes triggers as []", string.find(config.encodeDocument(fresh, config.leafOf(leaf)), '"triggers": []', 1, true) ~= nil)

local duplicateText = [[{"automations":[
	{"id":"daily-review","cron":"invalid","cwd":"/tmp","command":["true"],"note":"invalid-first"},
	{"id":"daily-review","cron":"* * * * *","cwd":"/tmp","command":["true"],"note":"selected"},
	{"id":"daily-review","cron":"0 * * * *","cwd":"/tmp","command":["false"],"note":"duplicate-last"}
]}]]
local duplicates = parse(duplicateText)
local selected, selectedIndex = config.findEntry(duplicates, "daily-review")
check("lookup selects the first valid definition, not an earlier invalid raw id", selected ~= nil and selected.def ~= nil and selectedIndex == 2)
local edited = definition()
edited.name = "Edited review"
local editedId, editProblem = config.upsert(duplicates, edited, duplicates.entries[2].revision)
local editedDoc = parse(config.encodeDocument(duplicates, config.leafOf(leaf)))
local editedDef = config.definitions(editedDoc)[1]
check("editing targets the selected valid definition", editedId == "daily-review" and editProblem == nil and editedDef ~= nil and editedDef.name == "Edited review" and #config.definitions(editedDoc) == 1)
check("editing preserves earlier invalid and later duplicate entries in place", #editedDoc.entries == 3 and #editedDoc.errors == 2 and editedDoc.entries[1].revision == parse(duplicateText).entries[1].revision and editedDoc.entries[3].revision == parse(duplicateText).entries[3].revision)
check("editing preserves the selected entry's unknown keys", string.find(editedDoc.entries[2].revision, '"note":"selected"', 1, true) ~= nil)

local duplicateToggle = parse(duplicateText)
local toggleOk, toggleProblem = config.toggle(duplicateToggle, "daily-review", false, duplicateToggle.entries[2].revision)
local toggledDoc = parse(config.encodeDocument(duplicateToggle, config.leafOf(leaf)))
local toggledDef = config.definitions(toggledDoc)[1]
check("toggle targets the valid definition behind an invalid raw id", toggleOk and toggleProblem == nil and toggledDef ~= nil and not toggledDef.enabled)
check("toggle preserves invalid and duplicate entries", toggledDoc.entries[1].revision == parse(duplicateText).entries[1].revision and toggledDoc.entries[3].revision == parse(duplicateText).entries[3].revision)
local invalidRevisionDoc = parse(duplicateText)
local invalidEdit, invalidEditProblem = config.upsert(invalidRevisionDoc, edited, invalidRevisionDoc.entries[1].revision)
check("an invalid raw entry's revision cannot authorize editing the valid definition", invalidEdit == nil and invalidEditProblem ~= nil and config.encodeDocument(invalidRevisionDoc, config.leafOf(leaf)) == config.encodeDocument(parse(duplicateText), config.leafOf(leaf)))
local invalidOnly = parse([[{"automations":[{"id":"daily-review","cron":"invalid","cwd":"/tmp","command":["true"]}]}]])
local reservedId, reservedProblem = config.upsert(invalidOnly, definition(), nil)
check("new definitions do not reuse an invalid raw entry's id", reservedId == nil and reservedProblem ~= nil and #invalidOnly.entries == 1)

for _, character in { "界", "😀" } do
	local named = definition()
	named.name = string.rep(character, 100)
	local namedDoc = parse([[{"automations":[]}]])
	local namedId, namedProblem = config.upsert(namedDoc, named, nil)
	local namedReloaded = config.definitions(parse(config.encodeDocument(namedDoc, config.leafOf(leaf))))[1]
	check("a long Unicode name is saved and reloaded without truncation: " .. character, namedId == named.id and namedProblem == nil and namedReloaded ~= nil and namedReloaded.name == named.name)
end

local function contains(text: string, fragment: string): boolean
	return string.find(text, fragment, 1, true) ~= nil
end

local invalidSource = [=[{"id":"invalid","cron":"no schedule","extra":null,"array":[],"object":{},"nested":{"null":null}}]=]
local originalSource = [=[{
	"i\u0064":"source",
	"name":"A \"quoted\" {name}",
	"cron":"* * * * *",
	"cwd":"/tmp",
	"command":["echo","a \"quote\" \\ slash } [,",""],
	"precheck":{"command":["true"],"extra":null},
	"e\u006eabled":true,
	"enabled":true,
	"extra":null,
	"array":[],
	"object":{},
	"nested":{"null":null,"values":[null,[],{},{"text":"} ] , : \" \\"}]},
	"esc\u0061ped":{"value":null}
}]=]
local preservedText = [=[
{
	"meta":null,
	"topArray":[],
	"topObject":{},
	"before":{"value":null,"text":"[ { \" }"},
	"auto\u006dations":[null,]=] .. invalidSource .. "," .. originalSource .. [=[,"braces } ] , \"",{}],
	"after":{"values":[null,[],{}]}
}
]=]

local function preservesUnknown(name: string, text: string)
	for _, fragment in {
		'"meta":null',
		'"topArray":[]',
		'"topObject":{}',
		[=["before":{"value":null,"text":"[ { \" }"}]=],
		'"after":{"values":[null,[],{}]}',
		'"extra":null',
		'"array":[]',
		'"object":{}',
		[=["nested":{"null":null,"values":[null,[],{},{"text":"} ] , : \" \\"}]}]=],
		[=["esc\u0061ped":{"value":null}]=],
		invalidSource,
	} do
		check(name .. " preserves " .. fragment, contains(text, fragment))
	end
	check(name .. " keeps null array entries", string.match(text, '"auto\\u006dations"%s*:%s*%[%s*null%s*,') ~= nil)
	local reloaded = parse(text)
	check(name .. " is readable with every original entry", reloaded.unsaveable == nil and #reloaded.entries >= 5 and #reloaded.errors == 4)
end

local creatingPreserved = parse(preservedText)
local newDefinition = definition()
newDefinition.name = 'New "quoted" name'
newDefinition.command = { "echo", 'new "argument" \\ {}[]', "" }
local createdPreservedId, createdPreservedProblem = config.upsert(creatingPreserved, newDefinition, nil)
local createdPreservedText = config.encodeDocument(creatingPreserved, config.leafOf(leaf))
preservesUnknown("create", createdPreservedText)
local createdPreservedDoc = parse(createdPreservedText)
local createdPreservedEntry = config.findEntry(createdPreservedDoc, newDefinition.id)
check("create appends a readable definition without changing existing entries", createdPreservedId == newDefinition.id and createdPreservedProblem == nil and #createdPreservedDoc.entries == 6 and contains(createdPreservedText, originalSource))
check("create escapes new known strings for JSON consumers", createdPreservedEntry ~= nil and createdPreservedEntry.def ~= nil and createdPreservedEntry.def.name == newDefinition.name and createdPreservedEntry.def.command[2] == newDefinition.command[2] and createdPreservedEntry.def.command[3] == "")

local togglingPreserved = parse(preservedText)
local sourceEntry = config.findEntry(togglingPreserved, "source")
check("escaped ids and null array slots select the original valid definition", sourceEntry ~= nil and sourceEntry == togglingPreserved.entries[3])
if sourceEntry then
	local changed, problem = config.toggle(togglingPreserved, "source", false, sourceEntry.revision)
	local saved = config.encodeDocument(togglingPreserved, config.leafOf(leaf))
	preservesUnknown("toggle", saved)
	local reloaded = config.definitions(parse(saved))[1]
	check("toggle readback changes only the enabled business value", changed and problem == nil and reloaded ~= nil and not reloaded.enabled and reloaded.name == 'A "quoted" {name}' and reloaded.command[2] == 'a "quote" \\ slash } [,' and reloaded.command[3] == "")
	check("toggle preserves untouched known source values", contains(saved, '"precheck":{"command":["true"],"extra":null}') and contains(saved, '"cron":"* * * * *"') and contains(saved, [=["i\u0064":"source"]=]) and not contains(saved, '"agent"'))
	local _, enabledCount = string.gsub(saved, '"enabled"%s*:', "")
	check("toggle replaces escaped and repeated enabled keys exactly once", enabledCount == 1 and not contains(saved, [=["e\u006eabled"]=]))
end

local editingPreserved = parse(preservedText)
local editSource = config.findEntry(editingPreserved, "source")
if editSource and editSource.def then
	local candidate = table.clone(editSource.def)
	candidate.name = 'Edited "name" \\ {}[]'
	candidate.command = { "echo", 'edited "argument" \\ {}[]', "" }
	candidate.precheck = nil
	candidate.triggers = { { kind = "event", source = "webhook", event = "example.updated", filter = "" } }
	local savedId, problem = config.upsert(editingPreserved, candidate, editSource.revision)
	local saved = config.encodeDocument(editingPreserved, config.leafOf(leaf))
	preservesUnknown("edit", saved)
	local reloaded = config.definitions(parse(saved))[1]
	check("edit readback contains the changed known values", savedId == "source" and problem == nil and reloaded ~= nil and reloaded.name == candidate.name and reloaded.command[2] == candidate.command[2] and reloaded.command[3] == "" and reloaded.precheck == nil and reloaded.triggers[1].kind == "event")
	local _, idCount = string.gsub(saved, '"id"%s*:%s*"source"', "")
	local _, enabledCount = string.gsub(saved, '"enabled"%s*:', "")
	check("edit rewrites escaped known keys without duplicating them", idCount == 1 and enabledCount == 1 and not contains(saved, [=["i\u0064"]=]) and not contains(saved, [=["e\u006eabled"]=]))
	local paused, pauseProblem = config.toggle(editingPreserved, "source", false, nil)
	local pausedText = config.encodeDocument(editingPreserved, config.leafOf(leaf))
	local pausedDef = config.definitions(parse(pausedText))[1]
	check("toggle after edit does not restore the original definition", paused and pauseProblem == nil and pausedDef ~= nil and pausedDef.name == candidate.name and not pausedDef.enabled)
	preservesUnknown("edit then toggle", pausedText)
end

for _, initial in { "{}", "{ \n\t }", '{"meta":null,"array":[],"object":{}}', '{"meta":null,"automations":[ \n ]}' } do
	local missing = parse(initial)
	local savedId, problem = config.upsert(missing, definition(), nil)
	local saved = config.encodeDocument(missing, config.leafOf(leaf))
	local reloaded = parse(saved)
	check("create handles missing or empty automations arrays", savedId == "daily-review" and problem == nil and reloaded.unsaveable == nil and #reloaded.entries == 1 and #config.definitions(reloaded) == 1)
	if contains(initial, '"meta"') then
		check("create retains metadata when adding the automations array", contains(saved, '"meta":null'))
	end
end
local newDocument = config.parseDocument(nil, support.decode)
local newId, newProblem = config.upsert(newDocument, definition(), nil)
local newReadback = parse(config.encodeDocument(newDocument, config.leafOf(leaf)))
check("create writes a readable new document", newId == "daily-review" and newProblem == nil and newReadback.unsaveable == nil and #config.definitions(newReadback) == 1)

for _, wrongShape in { "[]", '{"automations":null}', '{"automations":{}}' } do
	local wrong = parse(wrongShape)
	local savedId, problem = config.upsert(wrong, definition(), nil)
	check("a present non-array automations value cannot be overwritten", wrong.unsaveable ~= nil and savedId == nil and problem ~= nil)
end

for _, externalMember in {
	"",
	',"extra":null',
	',"extra":{"value":null}',
	',"extra":{"value":[]}',
	',"extra":{"value":{}}',
} do
	local prefix = '{"automations":[{"id":"source","cron":"* * * * *","cwd":"/tmp","command":["true"]'
	local opened = parse(prefix .. ',"extra":{"value":null,"removed":null}}]}')
	local externallyChangedText = prefix .. externalMember .. "}]}"
	local externallyChanged = parse(externallyChangedText)
	local originalRevision = opened.entries[1].revision
	local paused, pauseProblem = config.toggle(externallyChanged, "source", false, originalRevision)
	local draft = config.definitions(opened)[1]
	local savedId, saveProblem = config.upsert(externallyChanged, draft, originalRevision)
	check("raw unknown null and container changes invalidate toggle and edit revisions", externallyChanged.entries[1].revision ~= originalRevision and not paused and pauseProblem ~= nil and savedId == nil and saveProblem ~= nil)
	local readback = config.encodeDocument(externallyChanged, config.leafOf(leaf))
	check("conflicted mutations retain the external unknown data", parse(readback).unsaveable == nil and contains(readback, '{"id":"source","cron":"* * * * *","cwd":"/tmp","command":["true"]' .. externalMember .. "}"))
end

for _, originalEnabled in { "", ',"enabled":null', ',"e\\u006eabled":null' } do
	local changing = parse('{"automations":[{"id":"source","cron":"* * * * *","cwd":"/tmp","command":["true"],"extra":null' .. originalEnabled .. "}]}")
	local paused, pauseProblem = config.toggle(changing, "source", false, changing.entries[1].revision)
	local pausedText = config.encodeDocument(changing, config.leafOf(leaf))
	local pausedDef = config.definitions(parse(pausedText))[1]
	local _, count = string.gsub(pausedText, '"enabled"%s*:', "")
	check("toggle inserts or replaces a missing or null enabled field once", paused and pauseProblem == nil and pausedDef ~= nil and not pausedDef.enabled and count == 1 and contains(pausedText, '"extra":null') and not contains(pausedText, [=["e\u006eabled"]=]))
	local entry = config.findEntry(changing, "source")
	if entry and entry.def then
		local draft = table.clone(entry.def)
		draft.name = "Edited after toggle"
		local savedId, problem = config.upsert(changing, draft, entry.revision)
		local savedText = config.encodeDocument(changing, config.leafOf(leaf))
		local savedDef = config.definitions(parse(savedText))[1]
		check("edit after toggle retains raw unknown fields and the current enabled state", savedId == "source" and problem == nil and savedDef ~= nil and savedDef.name == draft.name and not savedDef.enabled and contains(savedText, '"extra":null'))
	end
end
local newPaused, newPauseProblem = config.toggle(newDocument, "daily-review", false, nil)
local newPausedDef = config.definitions(parse(config.encodeDocument(newDocument, config.leafOf(leaf))))[1]
check("toggle before the first serialization retains a newly created definition", newPaused and newPauseProblem == nil and newPausedDef ~= nil and not newPausedDef.enabled)

local function rejects(mutate: (config.Definition) -> ()): boolean
	local candidate = definition()
	mutate(candidate)
	local _, problem = config.upsert(parse([[{"automations":[]}]]), candidate, nil)
	return problem ~= nil
end
check("model flags cannot pass as a model", rejects(function(d)
	d.agent, d.command, d.instructions, d.model = "codex", {}, "do it", "--dangerous"
end))
check("a ref cannot look like an option", rejects(function(d)
	d.workspace, d.base_branch = "worktree", "--upload-pack=x"
end))
check("an event filter must be key=value", rejects(function(d)
	d.triggers = { { kind = "event", source = "github", event = "push", filter = "oops" } }
end))
check("an unknown event source is rejected", rejects(function(d)
	d.triggers = { { kind = "event", source = "carrier-pigeon", event = "push", filter = "" } }
end))
check("workspace none takes no cwd", rejects(function(d)
	d.workspace = "none"
end))
check("a prompt agent needs instructions", rejects(function(d)
	d.agent, d.command = "omp", {}
end))
check("an empty command array is rejected", rejects(function(d)
	d.command = {}
end))
check("an empty program is rejected", rejects(function(d)
	d.command = { "", "arg" }
end))
check("NUL in a command argument is rejected", rejects(function(d)
	d.command = { "echo", "a\0b" }
end))
check("NUL in a precheck argument is rejected", rejects(function(d)
	d.precheck = { command = { "test", "a\0b" }, timeout_seconds = 1 }
end))
for _, seconds in { 0, -1, math.huge, 0 / 0 } do
	check("a precheck timeout must be positive and finite", rejects(function(d)
		d.precheck = { command = { "true" }, timeout_seconds = seconds }
	end))
end
for _, grace in { 0, -1, math.huge, 0 / 0 } do
	check("grace must be at least one minute and finite", rejects(function(d)
		d.grace_minutes = grace
	end))
end
check("invalid UTF-8 in a name is rejected", rejects(function(d)
	d.name = string.char(255)
end))
check("control characters in a name are rejected", rejects(function(d)
	d.name = "First\nSecond"
end))
check("an empty name is rejected", rejects(function(d)
	d.name = ""
end))

if failures > 0 then
	error(failures .. " config checks failed")
end
return true
