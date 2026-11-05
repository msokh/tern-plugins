--!strict
local Input = require("./input")
local Model = require("./model")
local View = require("./view")

type State = Model.State
type Runtime = Model.Runtime

local Manager = {}

local BLOCK = "manager"
local FOCUS_DELAY_MS = 30

local function pref(saved: unknown, name: string): unknown
	if type(saved) == "table" then
		return rawget(saved, name)
	end
	return nil
end

local function newState(saved: unknown, args: { string }): State
	local tab: Model.Tab = if args[1] == "runs" or pref(saved, "tab") == "runs" then "runs" else "automations"
	local filter = pref(saved, "filter")
	local selected = pref(saved, "selected")
	return {
		mode = "overview",
		backTo = "overview",
		detailTab = "overview",
		tab = tab,
		filter = if filter == "enabled" or filter == "paused" then filter else "all",
		selected = if type(selected) == "string" then selected else nil,
		runId = nil,
		promptOpen = false,
		output = nil,
		search = Input.new(""),
		draft = nil,
		focus = nil,
		error = nil,
		notice = nil,
		noticeBad = false,
		discardArmed = false,
		snapshot = Model.emptySnapshot(),
		revisions = {},
		stale = true,
		baseline = nil,
		ids = {},
		cancel = nil,
	}
end

local function refresh(state: State, runtime: Runtime)
	local ok, snapshot = pcall(runtime.snapshot)
	state.stale = false
	if not ok then
		state.notice, state.noticeBad = `Could not read automations: {snapshot}`, true
		return
	end
	state.snapshot = snapshot
	state.revisions = {}
	for _, definition in snapshot.definitions do
		local revisionOk, revision = pcall(runtime.revision, definition.id)
		if revisionOk and revision ~= nil then
			state.revisions[definition.id] = revision
		end
	end
	if Model.find(snapshot.definitions, state.selected) == nil then
		state.selected = if snapshot.definitions[1] then snapshot.definitions[1].id else nil
		if state.mode == "detail" then
			state.mode = "overview"
		end
		if state.backTo == "detail" then
			state.backTo = "overview"
		end
	end
	if state.mode == "run" then
		local run = Model.findRun(snapshot.runs, state.runId)
		if run == nil then
			state.mode, state.runId, state.output = state.backTo, nil, nil
		else
			state.output = runtime.output(run.automationId, run.key)
		end
	end
end

local function visible(state: State): { Model.Definition }
	return Model.visible(state.snapshot.definitions, state.search.text, state.filter)
end

local function keepSelectionVisible(state: State)
	local shown = visible(state)
	if Model.find(shown, state.selected) == nil then
		state.selected = if shown[1] then shown[1].id else nil
	end
end

local function say(state: State, message: string, bad: boolean)
	state.notice, state.noticeBad = message, bad
end

local function focusLater(state: State, cx: BlockCx)
	local key = state.focus
	if key == nil then
		return
	end
	tern.timer(FOCUS_DELAY_MS, function()
		local id = state.ids[key]
		if id ~= nil then
			pcall(function()
				cx:frame({ { "focus", id } })
			end)
		end
	end)
end

local function focusField(state: State, cx: BlockCx, key: string?)
	state.focus = key
	local draft = state.draft
	local field = if key == "search" then state.search elseif draft and key then draft.fields[key] else nil
	if field then
		Input.focus(field)
	end
	focusLater(state, cx)
end

local function openEditor(state: State, cx: BlockCx, draft: Model.Draft, baseline: Model.Draft)
	state.backTo, state.mode, state.draft, state.baseline = state.mode, "editor", draft, baseline
	state.error, state.notice, state.discardArmed = nil, nil, false
	focusField(state, cx, "name")
end

local function leaveEditor(state: State)
	state.mode, state.draft, state.baseline = state.backTo, nil, nil
	state.error, state.discardArmed, state.focus = nil, false, nil
end

local function openDetail(state: State, id: string)
	state.selected, state.mode, state.detailTab, state.promptOpen = id, "detail", "overview", false
end

local function editSelected(state: State, cx: BlockCx, runtime: Runtime)
	refresh(state, runtime)
	local definition = Model.find(state.snapshot.definitions, state.selected)
	if definition == nil then
		say(state, "That automation no longer exists.", true)
		return
	end
	local revision = state.revisions[definition.id]
	if revision == nil then
		say(state, "This automation changed outside Tern and cannot be edited right now. Try again in a moment.", true)
		return
	end
	openEditor(state, cx, Model.draftFrom(definition, revision), Model.draftFrom(definition, revision))
end

local function save(state: State, cx: BlockCx, runtime: Runtime)
	local draft = state.draft
	if draft == nil then
		return
	end
	local result = Model.toDefinition(draft)
	local definition = result.definition
	if definition == nil then
		state.error = result.error
		focusField(state, cx, result.focus)
		return
	end
	local before = {}
	for _, existing in state.snapshot.definitions do
		before[existing.id] = true
	end
	local expected = if draft.id ~= nil then draft.revision else nil
	local ok, saved, message = pcall(runtime.save, definition, expected)
	if not ok then
		state.error = `Could not save: {saved}`
		return
	end
	if not saved then
		state.error = message or "Could not save this automation."
		return
	end
	refresh(state, runtime)
	if draft.id ~= nil then
		state.selected = draft.id
	else
		for _, created in state.snapshot.definitions do
			if not before[created.id] then
				state.selected = created.id
			end
		end
	end
	leaveEditor(state)
	say(state, `Saved {definition.name}.`, false)
	cx:toast("success", `Saved {definition.name}`)
end

local function runSelected(state: State, cx: BlockCx, runtime: Runtime)
	local definition = Model.find(state.snapshot.definitions, state.selected)
	if definition == nil then
		return
	end
	local ok, started, message = pcall(runtime.runNow, definition.id)
	if ok and started then
		say(state, `Queued {definition.name}. Run now skips the precheck.`, false)
		cx:toast("success", `Queued {definition.name}`, "Run now skips the precheck.")
	else
		say(state, message or (if ok then "Could not start this automation." else tostring(started)), true)
	end
	state.stale = true
end

local function toggleSelected(state: State, runtime: Runtime)
	local definition = Model.find(state.snapshot.definitions, state.selected)
	if definition == nil then
		return
	end
	local wanted = not definition.enabled
	local ok, changed, message = pcall(runtime.setEnabled, definition.id, wanted, state.revisions[definition.id])
	if ok and changed then
		say(state, `{if wanted then "Enabled" else "Paused"} {definition.name}.`, false)
	else
		say(state, message or (if ok then "Could not change this automation." else tostring(changed)), true)
	end
	refresh(state, runtime)
end

local function triggerOf(draft: Model.Draft, uid: number): Model.DraftTrigger?
	for _, trigger in draft.triggers do
		if trigger.uid == uid then
			return trigger
		end
	end
	return nil
end

local function firstTriggerField(trigger: Model.DraftTrigger): string
	return Model.triggerField(trigger.uid, if trigger.source == "schedule" then "cron" else "event")
end

local function isChoice(choices: { Model.Choice }, id: string): boolean
	for _, choice in choices do
		if choice.id == id then
			return true
		end
	end
	return false
end

local function editorAction(state: State, cx: BlockCx, draft: Model.Draft, act: string, value: string)
	state.error, state.discardArmed = nil, false
	if act == "add-trigger" then
		local trigger = Model.addTrigger(draft, "schedule")
		focusField(state, cx, firstTriggerField(trigger))
	elseif act == "remove-trigger" then
		Model.removeTrigger(draft, tonumber(value) or -1)
		state.focus = nil
	elseif act == "trigger-source" then
		local uid, source = string.match(value, "^(%d+):(.+)$")
		local trigger = if uid then triggerOf(draft, tonumber(uid) or -1) else nil
		if trigger and source and isChoice(Model.SOURCES, source) then
			trigger.source = source
			focusField(state, cx, firstTriggerField(trigger))
		end
	elseif act == "agent" and isChoice(Model.AGENTS, value) then
		draft.agent = value
		if state.focus == "instructions" or state.focus == "model" then
			focusField(state, cx, "name")
		end
	elseif act == "workspace" and isChoice(Model.WORKSPACES, value) then
		draft.workspace = value
	end
end

local function leaveRun(state: State)
	state.mode, state.runId, state.output = state.backTo, nil, nil
end

local function openSession(state: State, cx: BlockCx, runtime: Runtime)
	local run = Model.findRun(state.snapshot.runs, state.runId)
	if run == nil then
		return
	end
	runtime.openSession(run.automationId, run.key, function(ok, message)
		if not ok then
			say(state, message or "Could not show this session.", true)
		end
		pcall(function()
			cx:render()
		end)
	end)
end

local function onAction(state: State, ev: UiEvent, cx: BlockCx, runtime: Runtime)
	local act = if type(ev.act) == "string" then ev.act else ""
	local value = if type(ev.value) == "string" then ev.value else ""
	if state.mode == "run" then
		state.notice = nil
		if act == "back" then
			leaveRun(state)
		elseif act == "open-session" then
			openSession(state, cx, runtime)
		end
		return
	end
	if state.mode == "editor" then
		local draft = state.draft
		if act == "save" then
			save(state, cx, runtime)
		elseif act == "cancel" then
			leaveEditor(state)
		elseif draft ~= nil then
			editorAction(state, cx, draft, act, value)
		end
		return
	end
	state.notice = nil
	if act == "open-run" and Model.findRun(state.snapshot.runs, value) ~= nil then
		state.backTo, state.mode, state.runId, state.stale = state.mode, "run", value, true
		return
	elseif act == "toggle-prompt" then
		state.promptOpen = not state.promptOpen
		return
	elseif state.mode == "detail" and act == "back" then
		state.mode = "overview"
		return
	elseif state.mode == "detail" and act == "detail-tab" and (value == "overview" or value == "runs") then
		state.detailTab = value
		return
	end
	if act == "new" then
		openEditor(state, cx, Model.newDraft(), Model.newDraft())
	elseif act == "edit" then
		editSelected(state, cx, runtime)
	elseif act == "run" then
		runSelected(state, cx, runtime)
	elseif act == "toggle" then
		toggleSelected(state, runtime)
	elseif act == "select" and Model.find(state.snapshot.definitions, value) ~= nil then
		openDetail(state, value)
	elseif act == "tab" and (value == "automations" or value == "runs") then
		state.tab = value
	elseif act == "filter" and (value == "all" or value == "enabled" or value == "paused") then
		state.filter = value
		keepSelectionVisible(state)
	end
end

local function onEvent(state: State, ev: UiEvent, cx: BlockCx, runtime: Runtime)
	if ev.ev == "action" then
		onAction(state, ev, cx, runtime)
	elseif ev.ev == "focus" and type(ev.id) == "string" then
		for key, id in state.ids do
			if id == ev.id then
				state.focus = key
				local draft = state.draft
				local field = if key == "search" then state.search elseif draft then draft.fields[key] else nil
				if field then
					Input.focus(field)
				end
				return
			end
		end
	end
end

local function nextField(state: State, draft: Model.Draft, backwards: boolean): string?
	local order = Model.fieldOrder(draft)
	local index = if state.focus then table.find(order, state.focus) else nil
	if index == nil then
		return order[1]
	end
	return order[((index - 1 + (if backwards then -1 else 1)) % #order) + 1]
end

local function editorKey(state: State, key: Key, cx: BlockCx, runtime: Runtime): boolean
	local draft = state.draft
	if draft == nil then
		return false
	end
	local name = key.name
	if name == "escape" or name == "esc" then
		local baseline = state.baseline
		if state.discardArmed or baseline == nil or not Model.dirty(draft, baseline) then
			leaveEditor(state)
		else
			state.discardArmed = true
			state.error = "Press Esc again to discard your changes."
		end
		return true
	elseif name == "tab" then
		focusField(state, cx, nextField(state, draft, key.shift))
		return true
	elseif (key.meta or key.ctrl) and (name == "enter" or string.lower(name) == "s") then
		save(state, cx, runtime)
		return true
	end
	local field = if state.focus then draft.fields[state.focus] else nil
	if field == nil then
		return false
	end
	if name == "enter" and not field.multiline then
		focusField(state, cx, nextField(state, draft, false))
		return true
	elseif key.meta and string.lower(name) == "c" then
		local selection = Input.selection(field)
		if selection == "" then
			return false
		end
		cx:copy(selection)
		return true
	end
	local handled, message = Input.key(field, key)
	if not handled then
		return false
	end
	state.error, state.discardArmed = message, false
	focusLater(state, cx)
	return true
end

local function moveSelection(state: State, step: number)
	local shown = visible(state)
	local index = 1
	for i, definition in shown do
		if definition.id == state.selected then
			index = i
		end
	end
	local target = shown[math.clamp(index + step, 1, math.max(#shown, 1))]
	if target ~= nil then
		state.selected = target.id
	end
end

local function overviewKey(state: State, key: Key, cx: BlockCx): boolean
	local name = key.name
	if state.focus == "search" then
		if name == "escape" or name == "esc" then
			Input.setText(state.search, "")
			state.focus = nil
			keepSelectionVisible(state)
			return true
		elseif name == "up" or name == "down" then
			moveSelection(state, if name == "up" then -1 else 1)
			return true
		elseif name == "enter" then
			local target = state.selected
			state.focus = nil
			if target ~= nil then
				openDetail(state, target)
			end
			return true
		end
		local handled = Input.key(state.search, key)
		if not handled then
			return false
		end
		keepSelectionVisible(state)
		focusLater(state, cx)
		return true
	end
	if state.tab == "automations" and (name == "up" or name == "down") then
		moveSelection(state, if name == "up" then -1 else 1)
		return true
	elseif state.tab == "automations" and name == "enter" and state.selected ~= nil then
		openDetail(state, state.selected)
		return true
	elseif state.tab == "automations" and key.text == "/" and not (key.ctrl or key.meta) then
		focusField(state, cx, "search")
		return true
	end
	return false
end

function Manager.register(runtime: Runtime)
	tern.block.define(BLOCK, {
		font = "sans",
		init = function(cx: BlockCx, args: { string }, saved: unknown): State
			local state = newState(saved, args)
			local weak = setmetatable({ state }, { __mode = "v" })
			local cancel: (() -> ())? = nil
			cancel = runtime.subscribe(function()
				local live = weak[1]
				if live == nil then
					if cancel ~= nil then
						cancel()
						cancel = nil
					end
					return
				end
				live.stale = true
				local ok = pcall(function()
					cx:render()
				end)
				if not ok and cancel ~= nil then
					cancel()
					cancel = nil
					live.cancel = nil
				end
			end)
			state.cancel = cancel
			return state
		end,
		title = function(_: State): string?
			return "Automations"
		end,
		view = function(state: State, _: BlockCx): BlockView
			if state.stale then
				refresh(state, runtime)
			end
			return View.render(state, os.time())
		end,
		key = function(state: State, key: Key, cx: BlockCx): boolean?
			if state.mode == "editor" then
				return editorKey(state, key, cx, runtime)
			elseif state.mode == "run" or state.mode == "detail" then
				if key.name == "escape" or key.name == "esc" then
					if state.mode == "run" then
						leaveRun(state)
					else
						state.mode = "overview"
					end
					return true
				end
				return false
			end
			return overviewKey(state, key, cx)
		end,
		event = function(state: State, ev: UiEvent, cx: BlockCx)
			onEvent(state, ev, cx, runtime)
		end,
		save = function(state: State): { [string]: string? }
			return { tab = state.tab, filter = state.filter, selected = state.selected }
		end,
	})
end

return Manager
