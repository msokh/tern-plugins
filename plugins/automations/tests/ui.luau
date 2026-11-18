-- Behavior of the manager block's pure parts. Run: luau plugins/automations/tests/ui.luau
local Input = require("../input")
local Model = require("../model")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL " .. name)
	end
end

local function key(name: string, text: string?, mods: { shift: boolean?, meta: boolean?, ctrl: boolean? }?)
	local m = mods or {}
	return { name = name, text = text, ctrl = m.ctrl == true, alt = false, shift = m.shift == true, meta = m.meta == true }
end


local field = Input.new("")
for _, ch in { "日", "本", "😀" } do
	Input.key(field, key(ch, ch))
end
check("typing keeps code points whole", field.text == "日本😀" and Input.length(field) == 3)
check("cursor is reported in UTF-16 units", Input.props(field).cursor == 4)
Input.key(field, key("backspace"))
check("backspace removes one code point", field.text == "日本")
Input.key(field, key("a", nil, { meta = true }))
Input.key(field, key("x", "x"))
check("select all then typing replaces", field.text == "x")

local single = Input.new("ab")
local _, refusal = Input.key(single, key("paste", "x\u{0007}y"))
check("control characters are refused without edits", single.text == "ab" and refusal ~= nil)
Input.key(single, key("paste", "line\r\n"))
check("single-line paste drops its trailing break", single.text == "abline")

local multi = Input.new("one\ntwo", true)
multi.cursor = 1
Input.key(multi, key("down"))
check("down keeps the column on the next line", multi.cursor == 5)
Input.key(multi, key("enter"))
check("enter inserts a newline in multiline fields", multi.text == "one\nt\nwo")
Input.key(multi, key("paste", "a\r\nb"))
check("multiline paste normalizes line endings", multi.text == "one\nt\na\nbwo")

local undoable = Input.new("日本🧭\nOriginal instructions", true)
local originalText = undoable.text
Input.key(undoable, key("a", nil, { meta = true }))
Input.key(undoable, key("paste", "Replacement"))
Input.key(undoable, key("z", nil, { meta = true }))
check("undo restores replaced Unicode text and selection", undoable.text == originalText and Input.selection(undoable) == originalText)
Input.key(undoable, key("z", nil, { meta = true, shift = true }))
check("redo reapplies the replacement", undoable.text == "Replacement" and Input.selection(undoable) == "")
Input.key(undoable, key("z", nil, { ctrl = true }))
Input.key(undoable, key("paste", "Different"))
Input.key(undoable, key("z", nil, { meta = true, shift = true }))
check("a new edit discards the obsolete redo branch", undoable.text == "Different")
Input.setText(undoable, "Loaded instructions")
Input.key(undoable, key("z", nil, { meta = true }))
check("loading another value starts a new edit history", undoable.text == "Loaded instructions")

local typed = Input.new("Original")
Input.key(typed, key("a", nil, { meta = true }))
for _, character in { "N", "e", "w" } do
	Input.key(typed, key(character, character))
end
Input.key(typed, key("z", nil, { meta = true }))
check("undo restores a selection replaced by continuous typing", typed.text == "Original")
Input.key(typed, key("z", nil, { meta = true, shift = true }))
check("redo restores the complete typed replacement", typed.text == "New")
Input.focus(typed)
Input.key(typed, key("!", "!"))
Input.key(typed, key("z", nil, { meta = true }))
check("returning focus starts a separate typing group", typed.text == "New")
local unchanged = Input.new("A")
Input.key(unchanged, key("a", nil, { meta = true }))
Input.key(unchanged, key("a", "A"))
Input.key(unchanged, key("b", "B"))
Input.key(unchanged, key("z", nil, { meta = true }))
check("an unchanged replacement cannot swallow the next undo checkpoint", unchanged.text == "A")

local backward = Input.new("a🧭b")
Input.key(backward, key("left"))
Input.key(backward, key("backspace"))
Input.key(backward, key("z", nil, { meta = true }))
check("undo of backspace restores the original caret without selecting text", backward.text == "a🧭b" and backward.cursor == 2 and Input.selection(backward) == "")
Input.key(backward, key("x", "x"))
check("typing after backspace undo inserts instead of replacing", backward.text == "a🧭xb")
local forward = Input.new("a🧭b")
Input.key(forward, key("home"))
Input.key(forward, key("right"))
Input.key(forward, key("delete"))
Input.key(forward, key("z", nil, { meta = true }))
check("undo of forward delete restores the original caret without selecting text", forward.text == "a🧭b" and forward.cursor == 1 and Input.selection(forward) == "")
Input.key(forward, key("x", "x"))
check("typing after forward-delete undo preserves the restored character", forward.text == "ax🧭b")
local selected = Input.new("a🧭b")
Input.key(selected, key("a", nil, { meta = true }))
Input.key(selected, key("backspace"))
Input.key(selected, key("z", nil, { meta = true }))
check("undo restores a selection that existed before deletion", Input.selection(selected) == "a🧭b")
Input.key(selected, key("z", nil, { meta = true, shift = true }))
check("redo reapplies a selected deletion", selected.text == "")

-- Argv JSON ---------------------------------------------------------------------------------------

local original = { "run", 'say "hi"', "back\\slash", "日本", "tab\there" }
local decoded = Model.decodeArgv(Model.encodeArgv(original))
check("argv round-trips quotes, escapes and Unicode", decoded ~= nil and table.concat(decoded, "|") == table.concat(original, "|"))
local c1 = Model.decodeArgv(Model.encodeArgv({ "a\u{85}b\u{2028}c" }))
check("argv round-trips C1 and line-separator characters", c1 ~= nil and c1[1] == "a\u{85}b\u{2028}c")
check("encoded argv is always editable text", Input.valid(Model.encodeArgv({ "a\u{85}b\u{2028}c" }), false))
local pair = Model.decodeArgv('["a\\ud83d\\ude00"]')
check("surrogate escapes combine", pair ~= nil and pair[1] == "a😀")
check("non-arrays are rejected", select(2, Model.decodeArgv("omp -p x")) ~= nil)
check("non-string items are rejected", select(2, Model.decodeArgv("[1]")) ~= nil)
check("trailing text is rejected", select(2, Model.decodeArgv('["a"] x')) ~= nil)

-- Drafts ------------------------------------------------------------------------------------------

local function definition(id: string, overrides): Model.Definition
	local d = {
		id = id, name = "Example " .. id, instructions = "Review things.\nThen report.", agent = "omp", model = "",
		cwd = "/path/to/example-project", workspace = "existing", base_branch = "", command = {},
		triggers = { { kind = "schedule", cron = "0 9 * * 1-5" } }, precheck = nil, grace_minutes = 60, enabled = true,
	}
	for k, v in overrides or {} do
		d[k] = v
	end
	return d
end

local draft = Model.newDraft()
check("empty draft asks for a name", Model.toDefinition(draft).focus == "name")
Input.setText(draft.fields.name, "  Daily review  ")
check("agent drafts need instructions", Model.toDefinition(draft).focus == "instructions")
Input.setText(draft.fields.instructions, "Do it")
Input.setText(draft.fields[Model.triggerField(1, "cron")], "0 9 * * *")
Input.setText(draft.fields.cwd, "/path/to/example-project")
local built = Model.toDefinition(draft).definition
check("valid draft preserves its name", built ~= nil and built.name == "Daily review")
check("agent drafts send an empty command", built ~= nil and #built.command == 0)

draft.workspace = "none"
built = Model.toDefinition(draft).definition
check("workspace none sends no directory or branch", built ~= nil and built.cwd == "" and built.base_branch == "")

draft.agent = "command"
check("command agents need an argv", Model.toDefinition(draft).focus == "command")
Input.setText(draft.fields.command, '["omp", "-p", "@prompt.md"]')
Input.setText(draft.fields.model, "ignored")
built = Model.toDefinition(draft).definition
check("command agents send no instructions or model", built ~= nil and built.instructions == "" and built.model == "" and #built.command == 3)

Input.setText(draft.fields.precheck, '["check"]')
Input.setText(draft.fields.precheck_timeout, "0")
check("precheck needs a positive timeout", Model.toDefinition(draft).focus == "precheck_timeout")
Input.setText(draft.fields.precheck_timeout, "30")
built = Model.toDefinition(draft).definition
check("precheck is an object with seconds", built ~= nil and built.precheck ~= nil and built.precheck.timeout_seconds == 30)

local fractional = Model.draftFrom(definition("fractional", {
	precheck = { command = { "check" }, timeout_seconds = 1.5 },
}), "original")
local roundtrip = Model.toDefinition(fractional).definition
check("editing preserves a positive fractional precheck timeout", roundtrip ~= nil and roundtrip.precheck ~= nil and roundtrip.precheck.timeout_seconds == 1.5)

Model.addTrigger(draft, "github")
check("hidden fields leave Tab order", table.find(Model.fieldOrder(draft), "instructions") == nil and table.find(Model.fieldOrder(draft), "cwd") == nil)

local loaded = Model.draftFrom(definition("a", { triggers = { { kind = "event", source = "slack", event = "message", filter = "channel=ops*" } } }), "rev")
check("editing keeps id and revision", loaded.id == "a" and loaded.revision == "rev")
local round = Model.toDefinition(loaded).definition
check("editing round-trips an event trigger", round ~= nil and round.id == "a" and round.triggers[1].kind == "event" and round.triggers[1].filter == "channel=ops*")
local tabbed = Model.draftFrom(definition("a", { triggers = { { kind = "event", source = "github", event = "pull_request", filter = "repo=example-org/example-repo\tlabel=ready" } } }), "rev")
local tabbedBack = Model.toDefinition(tabbed).definition
check("editing keeps a tab-separated filter", tabbedBack ~= nil and tabbedBack.triggers[1].kind == "event" and tabbedBack.triggers[1].filter == "repo=example-org/example-repo label=ready")
check("untouched draft is not dirty", not Model.dirty(loaded, Model.draftFrom(definition("a", { triggers = { { kind = "event", source = "slack", event = "message", filter = "channel=ops*" } } }), "rev")))
local crlf = Model.draftFrom(definition("a", { instructions = "one\r\ntwo" }), "rev")
local crlfBack = Model.toDefinition(crlf)
check("editing normalizes CRLF instructions to LF instead of dropping them", crlfBack.definition ~= nil and crlfBack.definition.instructions == "one\ntwo")
Input.setText(loaded.fields.name, "Changed")
check("edited draft is dirty", Model.dirty(loaded, Model.draftFrom(definition("a", {}), "rev")))

local providerDefinition = definition("provider", {
	triggers = { { kind = "event", source = "github", event = "updated", filter = "" } },
})
local providerBaseline = Model.draftFrom(providerDefinition, "original")
local providerDraft = Model.draftFrom(providerDefinition, "original")
providerDraft.triggers[1].source = "webhook"
check("changing only an event provider dirties the draft", Model.dirty(providerDraft, providerBaseline))
providerDraft.triggers[1].source = "github"
check("restoring the original provider clears that change", not Model.dirty(providerDraft, providerBaseline))

-- Runs and lists ----------------------------------------------------------------------------------

local function run(phase: string, status: number?): Model.Run
	return { key = phase, id = "a:" .. phase, automationId = "a", automationName = "Example a", trigger = "manual", at = 1000, session = "s", phase = phase, status = status }
end
check("exit 0 is completed", Model.outcome(run("exited", 0)).label == "Completed")
check("nonzero exit is failed", Model.outcome(run("exited", 2)).tone == "bad")
check("launched means running, not complete", Model.outcome(run("launched")).label == "Running")
check("preparing is starting", Model.outcome(run("preparing")).label == "Starting")
check("missed and unknown are not success", Model.outcome(run("missed")).tone == "warn" and Model.outcome(run("unknown")).tone == "warn")
check("event trigger names its provider", Model.triggerLabel("event:github:pull_request.opened") == "GitHub event")

local defs = { definition("a", {}), definition("b", { enabled = false, name = "Weekly digest" }) }
check("filter by status", #Model.visible(defs, "", "paused") == 1 and Model.visible(defs, "", "paused")[1].id == "b")
check("search matches names case-insensitively", #Model.visible(defs, "DIGEST", "all") == 1)

local long = string.rep("🧭a", 100) .. "\nsecond line"
local summary = Model.summary(long)
check("a long first line is cut on a character boundary", utf8.len(summary) == 141 and string.sub(summary, -3) == "…")
check("the summary is the first non-blank line", Model.summary("\n\nlead\nnext") == "lead" and Model.summary("short") == "short")

if failures > 0 then
	error(`{failures} ui check(s) failed`)
end
print("ui tests passed")
