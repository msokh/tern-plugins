--!strict
local Input = require("./input")
local Model = require("./model")
local Page = require("./ui/page")

local ui = tern.ui

type Draft = Model.Draft
type Definition = Model.Definition
type State = Model.State

local View = {}

local RUNS_SHOWN = 100

local BADGE_TONE: { [Model.Tone]: string } = { ok = "success", bad = "error", warn = "warning", info = "info", muted = "muted" }
local DOT_TONE: { [Model.Tone]: string? } = { ok = "success", bad = "error", warn = "warning", info = "info" }

-- Every node that can sit on a focus path, and every sibling set, carries a key.
local function keyed(node: Node, key: string, grow: number?): Node
	local props = node.p or {}
	props.key = key
	props.grow = grow
	node.p = props
	return node
end

local function note(key: string, value: string, grow: number?): Node
	return keyed(ui.text({ ui.span(value, "muted") }), key, grow)
end

local function button(key: string, label: string, act: string, props: ButtonProps?): Node
	local p: ButtonProps = props or {}
	p.key = key
	p.actions = { click = act }
	return ui.button(label, p)
end

local function backButton(label: string, act: string): Node
	return keyed(ui.row({ button("back", label, act, { variant = "quiet", icon = "arrow-left" }) }), "nav")
end

local function title(value: string): Node
	return keyed(ui.text({ ui.span(value, "strong") }), "title")
end

local function notice(state: State): Node?
	local message = state.notice
	if message == nil then
		return nil
	end
	return keyed(ui.text({ if state.noticeBad then ui.span(message, "error") else message }), "notice")
end

local function statusBadge(definition: Definition): Node
	return keyed(ui.badge(if definition.enabled then "Enabled" else "Paused", if definition.enabled then "success" else "muted"), "status")
end

-- A group of choices as a joined button strip; the chosen one is pressed.
local function segment(key: string, choices: { Model.Choice }, current: string, act: string, prefix: string?): Node
	local buttons = {}
	for _, choice in choices do
		table.insert(buttons, button(`o-{choice.id}`, choice.label, `{act}={prefix or ""}{choice.id}`, { size = "sm", on = current == choice.id }))
	end
	return ui.node("buttons", { key = key, variant = "joined", size = "sm" }, buttons)
end

local function tabStrip(key: string, items: { { id: string, label: string } }, active: string, variant: string?): Node
	return ui.node("tabs", { key = key, items = items, active = active, variant = variant })
end

local Field = {}

-- `control` gets the path of the node that holds it, for callers that address the control by path.
function Field.render(path: string, key: string, props: { label: string, optional: boolean?, help: string? }, control: (string) -> Node): Node
	return ui.node("field", {
		key = `f-{key}`,
		label = if props.optional then `{props.label} (optional)` else props.label,
		hint = props.help,
	}, { control(`{path}.f-{key}`) })
end

local MACHINE_FIELDS = { "cron", "event", "filter", "cwd", "command", "precheck", "base_branch" }

local function inputNode(path: string, state: State, key: string, field: Input.Field, label: string, placeholder: string): Node
	local p = Input.props(field)
	state.ids[key] = `{path}.{key}`
	local mono = false
	for _, name in MACHINE_FIELDS do
		if string.find(key, name, 1, true) then
			mono = true
		end
	end
	return ui.node(if field.multiline then "editor" else "input", {
		key = key,
		variant = "field",
		mono = if mono then true else nil,
		aria = label,
		placeholder = placeholder,
		text = p.text,
		cursor = p.cursor,
		anchor = p.anchor,
	})
end

local function lastRun(state: State, id: string): Model.Run?
	return Model.runsOf(state.snapshot.runs, id, 1)[1]
end

local function resultCell(outcome: Model.Outcome, ago: string?): Cell
	local spans: { Span | string } = { outcome.label }
	if ago then
		table.insert(spans, ui.span(`  {ago}`, "muted"))
	end
	return { text = spans, dot = DOT_TONE[outcome.tone] }
end

local function automationsTable(state: State, shown: { Definition }, now: number): Node
	local rows: { { Cell } | TableRow } = {}
	for _, definition in shown do
		local lines = Model.triggerLines(definition)
		local more = if #lines > 1 then ` +{#lines - 1} more` else ""
		local run = lastRun(state, definition.id)
		local last: Cell = if run
			then resultCell(Model.outcome(run), Model.ago(run.at, now))
			else { ui.span("No runs yet", "muted") }
		table.insert(rows, {
			id = definition.id,
			cells = {
				{ ui.span(definition.name, "strong"), ui.span(`  {Model.workspaceLabel(definition.workspace)}`, "muted") },
				{ lines[1].kind, ui.span(`  {lines[1].detail}{more}`, "muted") },
				{ (Model.nextRun(definition, state.snapshot, now)) },
				last,
				{ badge = { text = if definition.enabled then "Enabled" else "Paused", tone = if definition.enabled then "success" else "muted" } },
			},
		})
	end
	local columns: { Col } = {
		{ id = "name", head = "Name", grow = 2 },
		{ id = "trigger", head = "Trigger", grow = 2 },
		{ id = "next", head = "Next run", grow = 1, priority = -1 },
		{ id = "last", head = "Last run", grow = 2, priority = -1 },
		{ id = "status", head = "Status" },
	}
	return keyed(ui.table(columns, rows, { selectable = true, selected = state.selected, empty = "No automations match your search." }), "list")
end

local function runsCard(state: State, now: number, only: string?): Node
	local runs = if only then Model.runsOf(state.snapshot.runs, only, RUNS_SHOWN) else state.snapshot.runs
	local rows: { { Cell } | TableRow } = {}
	for index, run in runs do
		if index > RUNS_SHOWN then
			break
		end
		local when = Model.when(run.at, now)
		local cells: { Cell } = {
			if only then { when } else { ui.span(run.automationName, "strong"), ui.span(`  {when}`, "muted") },
		}
		if only == nil then
			local definition = Model.find(state.snapshot.definitions, run.automationId)
			table.insert(cells, { if definition then Model.workspaceLabel(definition.workspace) else "-" })
		end
		table.insert(cells, { Model.triggerLabel(run.trigger) })
		table.insert(cells, { Model.duration(run) or "-" })
		table.insert(cells, resultCell(Model.outcome(run), nil))
		table.insert(rows, { id = run.id, cells = cells })
	end
	local columns: { Col } = { { id = "run", head = if only then "Started" else "Run", grow = 2 } }
	if only == nil then
		table.insert(columns, { id = "workspace", head = "Workspace", grow = 1, priority = -1 })
	end
	table.insert(columns, { id = "trigger", head = "Trigger", grow = 1 })
	table.insert(columns, { id = "duration", head = "Duration", priority = -1 })
	table.insert(columns, { id = "result", head = "Result" })
	local list = keyed(ui.table(columns, rows, { selectable = true, empty = "No runs yet. Runs appear here after an automation starts." }), "list")
	return ui.card("Run history", { list }, { key = "runs", icon = "clock", meta = { ui.span(Model.runSummary(runs), "muted") } })
end

local function runDetail(state: State, run: Model.Run, now: number): Node
	local definition = Model.find(state.snapshot.definitions, run.automationId)
	local agentId = if definition then definition.agent else "command"
	local outcome = Model.outcome(run)
	local live = run.pane ~= nil and (run.phase == "launched" or (run.phase == "exited" and run.status ~= nil and run.status ~= 0))
	local actions = { keyed(ui.badge(outcome.label, BADGE_TONE[outcome.tone]), "outcome") }
	if live then
		table.insert(actions, button("session", "Open session", "open-session", { icon = "terminal" }))
	end
	local nodes = {
		backButton(if state.backTo == "detail" then run.automationName else "Runs", "back"),
		keyed(ui.row({
			keyed(ui.col({ title(run.automationName), note("subtitle", `Run details · {Model.when(run.at, now)}`) }), "titles", 1),
			keyed(ui.row(actions), "actions"),
		}), "head"),
	}
	local banner = notice(state)
	if banner then
		table.insert(nodes, banner)
	end
	local session = run.session
	table.insert(nodes, ui.card("Run", {
		ui.kv({
			{ { "Started" }, { Model.when(run.at, now) } },
			{ { "Duration" }, { Model.duration(run) or "Running" } },
			{ { "Trigger" }, { Model.triggerLabel(run.trigger) } },
			{ { "Agent" }, { Model.label(Model.AGENTS, agentId) } },
			{ { "Session" }, { ui.span(session, "mono") } },
		}),
	}, { key = "meta", icon = "info" }))
	local problem = run.detail
	if problem == nil and run.status ~= nil and run.status ~= 0 then
		problem = `The program exited with status {run.status}.`
	end
	if problem ~= nil and outcome.tone ~= "ok" and outcome.tone ~= "info" then
		table.insert(nodes, ui.card("Problem", { ui.text({ problem }) }, { key = "problem", icon = "warn", tone = "warning" }))
	end
	local captured = state.output
	local content: Node
	if captured ~= nil and captured ~= "" then
		content = if agentId == "command" then ui.code(captured) else ui.md(captured)
	elseif outcome.tone == "info" then
		content = ui.text({ ui.span("The output appears here when the run ends.", "muted") })
	else
		content = ui.text({ ui.span("No output was saved for this run.", "muted") })
	end
	table.insert(nodes, ui.card("Output", { content }, { key = "output", icon = "terminal" }))
	return Page.render(nodes)
end

local function promptLines(value: string): Node
	local lines = {}
	for index, line in string.split(value, "\n") do
		table.insert(lines, keyed(ui.text({ if line == "" then " " else line }), `l{index}`))
	end
	return keyed(ui.lines(lines), "description")
end

local function automationDetail(state: State, definition: Definition, now: number): Node
	local isCommand = definition.instructions == ""
	local full = if isCommand then table.concat(definition.command, " ") else definition.instructions
	local clipped = Model.summary(full) ~= full
	local pairs: { { Spans } } = {}
	local lines = Model.triggerLines(definition)
	for index, line in lines do
		table.insert(pairs, { { if #lines > 1 then `Trigger {index}` else "Trigger" }, { line.kind, ui.span(`  {line.detail}`, "muted") } })
	end
	local agent = Model.label(Model.AGENTS, definition.agent)
	if definition.model ~= "" then
		agent ..= ` · {definition.model}`
	end
	local run = lastRun(state, definition.id)
	table.insert(pairs, { { "Workspace" }, { Model.workspaceLabel(definition.workspace) } })
	table.insert(pairs, { { "Agent" }, { agent } })
	table.insert(pairs, { { "Next run" }, { (Model.nextRun(definition, state.snapshot, now)) } })
	table.insert(pairs, { { "Last run" }, { if run then `{Model.outcome(run).label}, {Model.ago(run.at, now)}` else "Never" } })
	local body: { Node }
	if state.detailTab == "runs" then
		body = { runsCard(state, now, definition.id) }
	else
		local prompt: { Node } = { if state.promptOpen then promptLines(full) else keyed(ui.text({ Model.summary(full) }), "description") }
		local cardProps: CardProps = { key = "prompt", icon = if isCommand then "terminal" else "list" }
		if clipped then
			table.insert(prompt, button("more", if state.promptOpen then "Show less" else "Show more", "toggle-prompt", { variant = "quiet", size = "sm" }))
			cardProps["end"] = "main.prompt.more"
		end
		body = {
			ui.card("Details", { ui.kv(pairs) }, { key = "details", icon = "info" }),
			ui.card(if isCommand then "Command" else "Instructions", prompt, cardProps),
		}
	end
	local nodes = {
		backButton("Automations", "back"),
		keyed(ui.row({
			keyed(ui.row({ title(definition.name), statusBadge(definition) }), "titles", 1),
			keyed(ui.row({
				button("run", "Run now", "run", { variant = "primary", icon = "play" }),
				button("edit", "Edit", "edit"),
				button("toggle", if definition.enabled then "Pause" else "Enable", "toggle", { icon = if definition.enabled then "pause" else "power" }),
			}), "actions"),
		}), "head"),
		tabStrip("tabs", { { id = "overview", label = "Overview" }, { id = "runs", label = "Runs" } }, state.detailTab),
	}
	local banner = notice(state)
	if banner then
		table.insert(nodes, banner)
	end
	for _, node in body do
		table.insert(nodes, node)
	end
	return Page.render(nodes)
end

local function overview(state: State, now: number): Node
	local snapshot = state.snapshot
	local nodes = {
		keyed(ui.row({
			keyed(ui.col({
				keyed(ui.row({ title("Automations"), keyed(ui.badge(tostring(#snapshot.definitions), "muted"), "count") }), "line"),
				note("subtitle", "Run agents on a schedule or in response to events."),
			}), "titles", 1),
			button("new", "New automation", "new", { variant = "primary", icon = "plus" }),
		}), "head"),
	}
	if #snapshot.errors > 0 then
		local problems = {}
		for index, message in snapshot.errors do
			if index > 3 then
				table.insert(problems, note("more", `{#snapshot.errors - 3} more config problems`))
				break
			end
			table.insert(problems, keyed(ui.text({ message }), `e{index}`))
		end
		table.insert(nodes, ui.card("Config problems", problems, { key = "problems", icon = "warn", tone = "warning" }))
	end
	table.insert(nodes, tabStrip("tabs", { { id = "automations", label = "Automations" }, { id = "runs", label = "Runs" } }, state.tab))
	local banner = notice(state)
	if banner then
		table.insert(nodes, banner)
	end
	if state.tab == "runs" then
		table.insert(nodes, runsCard(state, now))
	elseif #snapshot.definitions == 0 then
		table.insert(nodes, ui.node("empty", {
			key = "empty",
			variant = "center",
			icon = "bolt",
			title = "No automations yet",
			text = "Create one to run an agent on a schedule or when an event arrives.",
		}, { button("create", "New automation", "new", { variant = "primary", icon = "plus" }) }))
	else
		local shown = Model.visible(snapshot.definitions, state.search.text, state.filter)
		local search = inputNode("main.toolbar", state, "search", state.search, "Search automations", "Search")
		search.p.icon = "search"
		search.p.grow = 1
		search.p.max = { w = "36ch" }
		table.insert(nodes, keyed(ui.row({
			search,
			tabStrip("filter", Model.FILTERS, state.filter, "segmented"),
		}), "toolbar"))
		table.insert(nodes, automationsTable(state, shown, now))
		table.insert(nodes, keyed(ui.row({
			note("count", `{#shown} of {#snapshot.definitions} automations`, 1),
			note("health", Model.healthLabel(snapshot.health)),
		}), "footer"))
	end
	return Page.render(nodes)
end

local function triggerBlock(path: string, state: State, draft: Draft, trigger: Model.DraftTrigger): Node
	local fields = draft.fields
	local here = `{path}.trigger-{trigger.uid}`
	local body: { Node }
	if trigger.source == "schedule" then
		local key = Model.triggerField(trigger.uid, "cron")
		body = {
			Field.render(`{here}.body`, key, { label = "Cron expression", help = "Five fields, local time: minute hour day month weekday." }, function(p)
				return inputNode(p, state, key, fields[key], "Cron expression", "0 9 * * 1-5")
			end),
		}
	else
		local eventKey = Model.triggerField(trigger.uid, "event")
		local filterKey = Model.triggerField(trigger.uid, "filter")
		body = {
			Field.render(`{here}.body`, eventKey, { label = "Event" }, function(p)
				return inputNode(p, state, eventKey, fields[eventKey], "Event", "pull_request.opened")
			end),
			Field.render(`{here}.body`, filterKey, {
				label = "Filter",
				optional = true,
				help = "key=value terms separated by spaces; a value may end with *. Blank matches any event.",
			}, function(p)
				return inputNode(p, state, filterKey, fields[filterKey], "Filter", "repo=example-org/example-repo")
			end),
		}
	end
	return keyed(ui.col({
		keyed(ui.row({
			keyed(ui.text({ ui.span("Trigger", "strong") }), "label", 1),
			button("remove", "", `remove-trigger={trigger.uid}`, { icon = "trash", variant = "quiet", size = "sm", title = "Remove trigger" }),
		}), "head"),
		segment("source", Model.SOURCES, trigger.source, "trigger-source", `{trigger.uid}:`),
		keyed(ui.col(body), "body"),
	}), `trigger-{trigger.uid}`)
end

local function editor(state: State, draft: Draft): Node
	local fields = draft.fields
	local function input(path: string, key: string, label: string, placeholder: string): Node
		return inputNode(path, state, key, fields[key], label, placeholder)
	end
	local hasEvent = false
	for _, trigger in draft.triggers do
		if trigger.source ~= "schedule" then
			hasEvent = true
		end
	end

	local task = "main.form.task"
	local taskNodes = {
		Field.render(task, "name", { label = "Name" }, function(p)
			return input(p, "name", "Name", "e.g. Review changes")
		end),
	}
	if draft.agent ~= "command" then
		table.insert(taskNodes, Field.render(task, "instructions", { label = "Instructions", help = "Describe the task, the expected output, and when the agent should stop." }, function(p)
			return input(p, "instructions", "Instructions", "What should the agent do?")
		end))
	end
	local triggerPath = `{task}.triggers`
	local triggerNodes = {}
	for _, trigger in draft.triggers do
		table.insert(triggerNodes, triggerBlock(triggerPath, state, draft, trigger))
	end
	table.insert(triggerNodes, button("add", "Add trigger", "add-trigger", { icon = "plus", size = "sm" }))
	table.insert(triggerNodes, note("help", if hasEvent then Model.EVENT_NOTE else "Any matching trigger starts a run. With none, only Run now starts it."))
	table.insert(taskNodes, keyed(ui.rule("Triggers"), "triggers-rule"))
	table.insert(taskNodes, keyed(ui.col(triggerNodes), "triggers"))

	local workspacePath = `{task}.workspace`
	local workspaceNodes = { segment("choice", Model.WORKSPACES, draft.workspace, "workspace") }
	if draft.workspace ~= "none" then
		table.insert(workspaceNodes, Field.render(workspacePath, "cwd", { label = if draft.workspace == "worktree" then "Repository path" else "Working directory" }, function(p)
			return input(p, "cwd", "Directory", "/path/to/example-project")
		end))
	end
	if draft.workspace == "worktree" then
		table.insert(workspaceNodes, Field.render(workspacePath, "base_branch", {
			label = "Base branch",
			optional = true,
			help = "Each run gets its own git worktree; existing worktrees are never removed.",
		}, function(p)
			return input(p, "base_branch", "Base branch", "Current branch")
		end))
	end
	table.insert(taskNodes, keyed(ui.rule("Workspace"), "workspace-rule"))
	table.insert(taskNodes, keyed(ui.col(workspaceNodes), "workspace"))

	local settings = "main.form.settings"
	local settingsNodes = {
		Field.render(settings, "agent", { label = "Agent" }, function(_)
			return segment("choice", Model.AGENTS, draft.agent, "agent")
		end),
	}
	if draft.agent ~= "command" then
		table.insert(settingsNodes, Field.render(settings, "model", { label = "Model", optional = true, help = "Leave blank for the agent's default." }, function(p)
			return input(p, "model", "Model", "Agent default")
		end))
	else
		table.insert(settingsNodes, Field.render(settings, "command", { label = "Command", help = "The program and its arguments as a JSON array." }, function(p)
			return input(p, "command", "Command", '["program", "argument"]')
		end))
	end
	table.insert(settingsNodes, Field.render(settings, "precheck", { label = "Precheck", optional = true, help = "Automatic runs only, as a JSON array. Run now skips it." }, function(p)
		return input(p, "precheck", "Precheck", '["program", "argument"]')
	end))
	if Model.trim(fields.precheck.text) ~= "" then
		table.insert(settingsNodes, Field.render(settings, "precheck_timeout", { label = "Precheck timeout", help = "Seconds." }, function(p)
			return input(p, "precheck_timeout", "Precheck timeout", "60")
		end))
	end
	table.insert(settingsNodes, Field.render(settings, "grace", { label = "Missed-run grace", help = "Minutes a missed schedule or event may still start." }, function(p)
		return input(p, "grace", "Missed-run grace", "60")
	end))
	table.insert(settingsNodes, keyed(ui.rule("Permissions"), "permissions-rule"))
	table.insert(settingsNodes, note("permissions", Model.PERMISSION_NOTE))

	local editing = draft.id ~= nil
	local nodes = {
		backButton("Automations", "cancel"),
		keyed(ui.row({
			keyed(ui.col({
				title(if editing then "Edit automation" else "New automation"),
				note("subtitle", "Define when your agent runs and what it should do."),
			}), "titles", 1),
			keyed(ui.row({
				button("cancel", "Cancel", "cancel"),
				button("save", if editing then "Save changes" else "Create automation", "save", { variant = "primary" }),
			}), "actions"),
		}), "head"),
	}
	if state.error then
		table.insert(nodes, keyed(ui.text({ ui.span(state.error, "error") }), "error"))
	end

	local taskCard = ui.card("Task", taskNodes, { key = "task", icon = "list", grow = 1, basis = 0 })
	local settingsCard = ui.card("Execution", settingsNodes, { key = "settings", icon = "bolt", grow = 1, basis = 0 })
	table.insert(nodes, ui.node("row", { key = "form", gap = "lg", align = "start" }, { taskCard, settingsCard }))
	return Page.render(nodes)
end

function View.render(state: State, now: number): BlockView
	state.ids = {}
	local draft = state.draft
	if state.mode == "editor" and draft then
		return { main = editor(state, draft) }
	end
	local run = if state.mode == "run" then Model.findRun(state.snapshot.runs, state.runId) else nil
	if run then
		return { main = runDetail(state, run, now) }
	end
	local definition = if state.mode == "detail" then Model.find(state.snapshot.definitions, state.selected) else nil
	if definition then
		return { main = automationDetail(state, definition, now) }
	end
	return { main = overview(state, now) }
end

return View
