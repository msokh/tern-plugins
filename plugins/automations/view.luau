--!strict
local Input = require("./input")
local Model = require("./model")

local ui = tern.ui

type Props = { [string]: unknown }
type Ctx = { path: string, ids: { [string]: string } }
type Draft = Model.Draft
type Definition = Model.Definition
type State = Model.State

local View = {}

local RUNS_SHOWN = 100

local TONE_ROLE: { [Model.Tone]: string } = {
	ok = "automations.resultOk",
	bad = "automations.resultBad",
	warn = "automations.resultWarn",
	info = "automations.resultInfo",
	muted = "automations.resultMuted",
}
local TABLE_DOT: { [Model.Tone]: string? } = { ok = "success", bad = "error", warn = "warning", info = "info" }

local function sub(ctx: Ctx, key: string): Ctx
	return { path = `{ctx.path}.{key}`, ids = ctx.ids }
end

local function box(ctx: Ctx, kind: string, key: string, role: string, extra: Props?, build: (Ctx) -> { Node }): Node
	local props: Props = extra or {}
	props.key, props.role = key, role
	return ui.node(kind, props, build(sub(ctx, key)))
end

local function text(key: string, value: string, role: string, extra: Props?): Node
	local props: Props = extra or {}
	props.key, props.text, props.role = key, value, role
	return ui.node("text", props)
end

local function button(key: string, label: string, action: string, role: string, pressed: boolean?, title: string?): Node
	local attrs: { [string]: string }? = nil
	if pressed ~= nil then
		attrs = { ["aria-pressed"] = if pressed then "true" else "false" }
	end
	return ui.el("button", { key = key, role = role, text = label, title = title, attrs = attrs, mark = if pressed then "pick" else nil, actions = { click = action } })
end

local function dot(key: string, tone: Model.Tone): Node
	return ui.el("div", { key = key, role = `automations.dot.{tone}` })
end

local function outcomeLine(key: string, outcome: Model.Outcome): Node
	return ui.node("row", { key = key, role = "automations.result" }, {
		dot("dot", outcome.tone),
		text("label", outcome.label, TONE_ROLE[outcome.tone]),
	})
end

local function segment(ctx: Ctx, key: string, choices: { Model.Choice }, current: string, act: string, prefix: string?): Node
	return box(ctx, "row", key, "automations.segment", nil, function(_)
		local out = {}
		for _, choice in choices do
			local value = (prefix or "") .. choice.id
			table.insert(out, button(`o-{choice.id}`, choice.label, `{act}={value}`, "automations.segmentButton", current == choice.id))
		end
		return out
	end)
end

local function inputNode(ctx: Ctx, state: State, key: string, field: Input.Field, label: string, placeholder: string): Node
	local p = Input.props(field)
	state.ids[key] = `{ctx.path}.{key}`
	return ui.node(if field.multiline then "editor" else "input", {
		key = key,
		role = if field.multiline then "automations.editor" else "automations.input",
		aria = label,
		placeholder = placeholder,
		text = p.text,
		cursor = p.cursor,
		anchor = p.anchor,
		mark = if state.focus == key then "pick" else nil,
	})
end

local function labelled(ctx: Ctx, key: string, label: string, optional: boolean, help: string?, control: (Ctx) -> Node): Node
	return box(ctx, "col", `f-{key}`, "automations.field", nil, function(c)
		local head = { text("label", label, "automations.fieldLabel") }
		if optional then
			table.insert(head, text("optional", "Optional", "automations.optional"))
		end
		local out = { ui.node("row", { key = "head", role = "automations.fieldHead" }, head), control(c) }
		if help then
			table.insert(out, text("help", help, "automations.help"))
		end
		return out
	end)
end


local HEADS: { [string]: string } =
	{ name = "Name", trigger = "Trigger", next = "Next run", last = "Last run", status = "Status" }

local function statusPill(definition: Definition): Node
	return text("status", if definition.enabled then "Enabled" else "Paused", "automations.pill", {
		mark = if definition.enabled then "pick" else nil,
	})
end

local function lastRun(state: State, id: string): Model.Run?
	return Model.runsOf(state.snapshot.runs, id, 1)[1]
end

local function cell(state: State, column: string, definition: Definition, now: number): Node
	local role = `automations.col.{column}`
	if column == "name" then
		return ui.node("col", { key = column, role = role }, {
			text("name", definition.name, "automations.name"),
			text("meta", Model.workspaceLabel(definition.workspace), "automations.secondary"),
		})
	elseif column == "trigger" then
		local lines = Model.triggerLines(definition)
		local more = if #lines > 1 then ` +{#lines - 1} more` else ""
		return ui.node("col", { key = column, role = role }, {
			text("kind", lines[1].kind, "automations.name"),
			text("detail", lines[1].detail .. more, "automations.secondary"),
		})
	elseif column == "next" then
		local label = Model.nextRun(definition, state.snapshot, now)
		return ui.node("col", { key = column, role = role }, { text("when", label, "automations.value") })
	elseif column == "last" then
		local run = lastRun(state, definition.id)
		if not run then
			return ui.node("col", { key = column, role = role }, {
				text("none", "No runs yet", "automations.secondary"),
			})
		end
		return ui.node("col", { key = column, role = role }, {
			outcomeLine("result", Model.outcome(run)),
			text("ago", Model.ago(run.at, now), "automations.secondary"),
		})
	end
	return ui.node("col", { key = column, role = role }, { statusPill(definition) })
end

local function tableList(ctx: Ctx, state: State, shown: { Definition }, now: number): Node
	local columns = { "name", "trigger", "next", "last", "status" }
	return box(ctx, "col", "list", "automations.list", nil, function(_)
		local out = {}
		local heads = {}
		for _, column in columns do
			table.insert(heads, text(column, HEADS[column], `automations.th automations.col.{column}`))
		end
		table.insert(out, ui.node("row", { key = "head", role = "automations.tableHead" }, heads))
		for _, definition in shown do
			local cells = {}
			for _, column in columns do
				table.insert(cells, cell(state, column, definition, now))
			end
			table.insert(out, ui.node("row", {
				key = `r-{definition.id}`,
				role = "automations.row",
				mark = if state.selected == definition.id then "pick" else nil,
				aria = definition.name,
				actions = { click = `select={definition.id}` },
			}, cells))
		end
		if #shown == 0 then
			table.insert(out, text("none", "No automations match your search.", "automations.emptyRow"))
		end
		table.insert(out, ui.node("row", { key = "footer", role = "automations.listFooter" }, {
			text("count", `{#shown} of {#state.snapshot.definitions} automations`, "automations.note"),
		}))
		return out
	end)
end

local function meta(key: string, label: string, values: { Node }): Node
	return ui.node("row", { key = key, role = "automations.metaRow" }, {
		text("label", label, "automations.metaLabel"),
		ui.node("col", { key = "value", role = "automations.metaValue" }, values),
	})
end

local RUN_COLUMNS = {
	{ id = "run", head = "Run" },
	{ id = "workspace", head = "Workspace" },
	{ id = "trigger", head = "Trigger" },
	{ id = "duration", head = "Duration" },
	{ id = "result", head = "Result" },
}

local function workspaceOf(state: State, run: Model.Run): string
	local definition = Model.find(state.snapshot.definitions, run.automationId)
	return if definition then Model.workspaceLabel(definition.workspace) else "-"
end

local function runsTable(state: State, now: number, only: string?): Node
	local runs = if only then Model.runsOf(state.snapshot.runs, only, RUNS_SHOWN) else state.snapshot.runs
	local heads = {}
	for _, column in RUN_COLUMNS do
		if only == nil or column.id ~= "workspace" then
			table.insert(heads, text(column.id, if only and column.id == "run" then "Started" else column.head, `automations.th automations.runCol.{column.id}`))
		end
	end
	local out = {
		ui.node("row", { key = "summary", role = "automations.runsSummary" }, {
			text("title", "Run history", "automations.h3", { grow = 1 }),
			text("count", Model.runSummary(runs), "automations.note"),
		}),
		ui.node("row", { key = "head", role = "automations.tableHead" }, heads),
	}
	for index, run in runs do
		if index > RUNS_SHOWN then
			break
		end
		local cells = {
			ui.node("col", { key = "run", role = "automations.runCol.run" }, if only then {
				text("when", Model.when(run.at, now), "automations.name"),
			} else {
				text("name", run.automationName, "automations.name"),
				text("when", Model.when(run.at, now), "automations.secondary"),
			}),
		}
		if only == nil then
			table.insert(cells, text("workspace", workspaceOf(state, run), "automations.value automations.runCol.workspace"))
		end
		table.insert(cells, text("trigger", Model.triggerLabel(run.trigger), "automations.value automations.runCol.trigger"))
		table.insert(cells, text("duration", Model.duration(run) or "-", "automations.value automations.runCol.duration"))
		table.insert(cells, ui.node("col", { key = "result", role = "automations.runCol.result" }, {
			outcomeLine("outcome", Model.outcome(run)),
		}))
		table.insert(out, ui.node("row", {
			key = `run-{run.id}`,
			role = "automations.runRow",
			aria = `{run.automationName}, {Model.when(run.at, now)}`,
			actions = { click = `open-run={run.id}` },
		}, cells))
	end
	if #runs == 0 then
		table.insert(out, text("none", "No runs yet. Runs appear here after an automation starts.", "automations.emptyRow"))
	end
	return ui.node("col", { key = "runs", role = "automations.runsPanel" }, out)
end

local function metaCell(key: string, label: string, value: string): Node
	return ui.node("col", { key = key, role = "automations.metaCell" }, {
		text("label", label, "automations.kicker"),
		text("value", value, "automations.value"),
	})
end

local function runDetail(state: State, run: Model.Run, now: number): Node
	local definition = Model.find(state.snapshot.definitions, run.automationId)
	local agentId = if definition then definition.agent else "command"
	local outcome = Model.outcome(run)
	local live = run.pane ~= nil and (run.phase == "launched" or (run.phase == "exited" and run.status ~= nil and run.status ~= 0))
	local head = {
		outcomeLine("outcome", outcome),
	}
	if live then
		table.insert(head, button("session", "Open session", "open-session", "automations.button"))
	end
	local problem = run.detail
	if problem == nil and run.status ~= nil and run.status ~= 0 then
		problem = `The program exited with status {run.status}.`
	end
	local body = {}
	if problem ~= nil and outcome.tone ~= "ok" and outcome.tone ~= "info" then
		table.insert(body, ui.node("col", { key = "problem", role = "automations.problems" }, {
			text("v", problem, "automations.problem"),
		}))
	end
	local captured = state.output
	local content: Node
	if captured ~= nil and captured ~= "" then
		content = if agentId == "command" then ui.code(captured) else ui.md(captured)
	elseif outcome.tone == "info" then
		content = text("none", "The output appears here when the run ends.", "automations.secondary")
	else
		content = text("none", "No output was saved for this run.", "automations.secondary")
	end
	table.insert(body, ui.node("col", { key = "output", role = "automations.output" }, {
		text("title", "Output", "automations.h3"),
		ui.node("col", { key = "text", role = "automations.outputText" }, { content }),
	}))
	local nodes = {
		ui.node("row", { key = "nav", role = "automations.nav" }, {
			button("back", if state.backTo == "detail" then `← {run.automationName}` else "← Runs", "back", "automations.backButton"),
		}),
		ui.node("row", { key = "head", role = "automations.head" }, {
			ui.node("col", { key = "titles", role = "automations.titles", grow = 1 }, {
				text("title", run.automationName, "automations.title"),
				text("subtitle", `Run details · {Model.when(run.at, now)}`, "automations.secondary"),
			}),
			ui.node("row", { key = "actions", role = "automations.actions" }, head),
		}),
	}
	if state.notice then
		table.insert(nodes, text("notice", state.notice, if state.noticeBad then "automations.error" else "automations.noticeText"))
	end
	table.insert(nodes, ui.node("col", { key = "card", role = "automations.formCard" }, {
		ui.node("row", { key = "meta", role = "automations.runMeta" }, {
			metaCell("started", "STARTED", Model.when(run.at, now)),
			metaCell("duration", "DURATION", Model.duration(run) or "Running"),
			metaCell("trigger", "TRIGGER", Model.triggerLabel(run.trigger)),
			metaCell("agent", "AGENT", Model.label(Model.AGENTS, agentId)),
			metaCell("session", "SESSION", run.session),
		}),
		ui.node("col", { key = "body", role = "automations.runBody" }, body),
	}))
	return ui.node("col", { key = "page", role = "automations.page" }, nodes)
end

local function automationDetail(state: State, definition: Definition, now: number): Node
	local isCommand = definition.instructions == ""
	local full = if isCommand then table.concat(definition.command, " ") else definition.instructions
	local clipped = Model.summary(full) ~= full
	local triggers = {}
	for index, line in Model.triggerLines(definition) do
		table.insert(triggers, text(`t{index}`, `{line.kind} · {line.detail}`, "automations.value"))
	end
	local agent = Model.label(Model.AGENTS, definition.agent)
	if definition.model ~= "" then
		agent ..= ` · {definition.model}`
	end
	local run = lastRun(state, definition.id)
	local body: Node
	if state.detailTab == "runs" then
		body = runsTable(state, now, definition.id)
	else
		body = ui.node("col", { key = "card", role = "automations.formCard" }, {
			ui.node("col", { key = "details", role = "automations.section" }, {
				meta("trigger", if #triggers > 1 then "Triggers" else "Trigger", triggers),
				meta("workspace", "Workspace", { text("v", Model.workspaceLabel(definition.workspace), "automations.value") }),
				meta("agent", "Agent", { text("v", agent, "automations.value") }),
				meta("next", "Next run", { text("v", Model.nextRun(definition, state.snapshot, now), "automations.value") }),
				meta("last", "Last run", {
					text("v", if run then `{Model.outcome(run).label}, {Model.ago(run.at, now)}` else "Never", "automations.value"),
				}),
			}),
			ui.node("col", { key = "prompt", role = "automations.section" }, {
				ui.node("row", { key = "head", role = "automations.sectionTitle" }, {
					text("title", if isCommand then "Command" else "Instructions", "automations.h3"),
					if clipped then button("more", if state.promptOpen then "Show less" else "Show more", "toggle-prompt", "automations.linkButton") else text("none", "", "automations.note"),
				}),
				text("description", if state.promptOpen then full else Model.summary(full), if state.promptOpen then "automations.description automations.descriptionOpen" else "automations.description"),
			}),
		})
	end
	local nodes = {
		ui.node("row", { key = "nav", role = "automations.nav" }, {
			button("back", "← Automations", "back", "automations.backButton"),
		}),
		ui.node("row", { key = "head", role = "automations.head" }, {
			ui.node("row", { key = "titles", role = "automations.titleLine", grow = 1 }, {
				text("title", definition.name, "automations.title"),
				statusPill(definition),
			}),
			ui.node("row", { key = "actions", role = "automations.actions" }, {
				button("run", "Run now", "run", "automations.primaryButton"),
				button("edit", "Edit", "edit", "automations.button"),
				button("toggle", if definition.enabled then "Pause" else "Enable", "toggle", "automations.button"),
			}),
		}),
		ui.node("row", { key = "tabs", role = "automations.tabs" }, {
			button("t-overview", "Overview", "detail-tab=overview", "automations.tab", state.detailTab == "overview"),
			button("t-runs", "Runs", "detail-tab=runs", "automations.tab", state.detailTab == "runs"),
		}),
	}
	if state.notice then
		table.insert(nodes, text("notice", state.notice, if state.noticeBad then "automations.error" else "automations.noticeText"))
	end
	table.insert(nodes, body)
	return ui.node("col", { key = "page", role = "automations.page" }, nodes)
end

local function emptyState(): Node
	return ui.node("col", { key = "empty", role = "automations.empty" }, {
		text("title", "No automations yet", "automations.emptyTitle"),
		text("body", "Create one to run an agent on a schedule or when an event arrives.", "automations.secondary"),
		button("create", "New automation", "new", "automations.primaryButton"),
	})
end

local function overview(ctx: Ctx, state: State, now: number): Node
	local snapshot = state.snapshot
	local children = {
		ui.node("row", { key = "head", role = "automations.head" }, {
			ui.node("col", { key = "titles", role = "automations.titles", grow = 1 }, {
				ui.node("row", { key = "line", role = "automations.titleLine" }, {
					text("title", "Automations", "automations.title"),
					text("count", tostring(#snapshot.definitions), "automations.count"),
				}),
				text("subtitle", "Run agents on a schedule or in response to events.", "automations.secondary"),
			}),
			button("new", "New automation", "new", "automations.primaryButton"),
		}),
	}
	if #snapshot.errors > 0 then
		local lines = {}
		for index, message in snapshot.errors do
			if index > 3 then
				table.insert(lines, text("more", `{#snapshot.errors - 3} more config problems`, "automations.note"))
				break
			end
			table.insert(lines, text(`e{index}`, message, "automations.problem"))
		end
		table.insert(children, ui.node("col", { key = "problems", role = "automations.problems" }, lines))
	end
	table.insert(children, ui.node("row", { key = "tabs", role = "automations.tabs" }, {
		button("t-automations", "Automations", "tab=automations", "automations.tab", state.tab == "automations"),
		button("t-runs", "Runs", "tab=runs", "automations.tab", state.tab == "runs"),
	}))
	if state.notice then
		table.insert(children, text("notice", state.notice, if state.noticeBad then "automations.error" else "automations.noticeText"))
	end
	if state.tab == "runs" then
		table.insert(children, runsTable(state, now))
	elseif #snapshot.definitions == 0 then
		table.insert(children, emptyState())
	else
		local shown = Model.visible(snapshot.definitions, state.search.text, state.filter)
		table.insert(children, box(ctx, "row", "toolbar", "automations.toolbar", nil, function(c)
			return {
				box(c, "row", "tools", "automations.toolGroup", nil, function(t)
					return {
						inputNode(t, state, "search", state.search, "Search automations", "Search automations…"),
						segment(t, "filter", Model.FILTERS, state.filter, "filter"),
					}
				end),
				text("health", Model.healthLabel(snapshot.health), "automations.note"),
			}
		end))
		table.insert(children, ui.node("row", { key = "layout", role = "automations.layout" }, { tableList(ctx, state, shown, now) }))
	end
	return ui.node("col", { key = "page", role = "automations.page" }, children)
end

local function triggerCard(ctx: Ctx, state: State, draft: Draft, trigger: Model.DraftTrigger): Node
	local fields = draft.fields
	return box(ctx, "col", `trigger-{trigger.uid}`, "automations.triggerBox", nil, function(c)
		return {
			ui.node("row", { key = "head", role = "automations.triggerHead" }, {
				text("title", "Trigger", "automations.fieldLabel", { grow = 1 }),
				button("remove", "×", `remove-trigger={trigger.uid}`, "automations.iconButton", nil, "Remove trigger"),
			}),
			segment(c, "source", Model.SOURCES, trigger.source, "trigger-source", `{trigger.uid}:`),
			box(c, "col", "body", "automations.triggerFields", nil, function(b)
				if trigger.source == "schedule" then
					local key = Model.triggerField(trigger.uid, "cron")
					return {
						labelled(b, key, "Cron expression", false, "Five fields, local time: minute hour day month weekday.", function(f)
							return inputNode(f, state, key, fields[key], "Cron expression", "0 9 * * 1-5")
						end),
					}
				end
				local eventKey = Model.triggerField(trigger.uid, "event")
				local filterKey = Model.triggerField(trigger.uid, "filter")
				return {
					labelled(b, eventKey, "Event", false, nil, function(f)
						return inputNode(f, state, eventKey, fields[eventKey], "Event", "pull_request.opened")
					end),
					labelled(b, filterKey, "Filter", true, "key=value terms separated by spaces; a value may end with *. Blank matches any event.", function(f)
						return inputNode(f, state, filterKey, fields[filterKey], "Filter", "repo=example-org/example-repo")
					end),
				}
			end),
		}
	end)
end

local function editor(ctx: Ctx, state: State, draft: Draft): Node
	ctx = sub(sub(ctx, "card"), "grid")
	local fields = draft.fields
	local function input(c: Ctx, key: string, label: string, placeholder: string): Node
		return inputNode(c, state, key, fields[key], label, placeholder)
	end
	local hasEvent = false
	for _, trigger in draft.triggers do
		if trigger.source ~= "schedule" then
			hasEvent = true
		end
	end
	local main = box(ctx, "col", "main", "automations.formMain", nil, function(c)
		local out = {
			text("kicker", "TASK DEFINITION", "automations.kicker"),
			labelled(c, "name", "Name", false, nil, function(f)
				return input(f, "name", "Name", "e.g. Review changes")
			end),
		}
		if draft.agent ~= "command" then
			table.insert(out, labelled(c, "instructions", "Instructions", false, "Describe the task, the expected output, and when the agent should stop.", function(f)
				return input(f, "instructions", "Instructions", "What should the agent do?")
			end))
		end
		table.insert(out, box(c, "col", "triggers", "automations.formSection", nil, function(t)
			return {
				text("title", "Triggers", "automations.fieldLabel"),
				box(t, "col", "cards", "automations.triggerList", nil, function(cards)
					local items = {}
					for _, trigger in draft.triggers do
						table.insert(items, triggerCard(cards, state, draft, trigger))
					end
					table.insert(items, button("add", "Add trigger", "add-trigger", "automations.button"))
					table.insert(items, text("help", if hasEvent then Model.EVENT_NOTE else "Any matching trigger starts a run. With none, only Run now starts it.", "automations.help"))
					return items
				end),
			}
		end))
		table.insert(out, box(c, "col", "workspaceBox", "automations.formSection", nil, function(w)
			return {
				text("title", "Workspace", "automations.fieldLabel"),
				box(w, "col", "items", "automations.triggerList", nil, function(items)
					local parts = { segment(items, "workspace", Model.WORKSPACES, draft.workspace, "workspace") }
					if draft.workspace ~= "none" then
						table.insert(parts, labelled(items, "cwd", if draft.workspace == "worktree" then "Repository path" else "Working directory", false, nil, function(f)
							return input(f, "cwd", "Directory", "/path/to/example-project")
						end))
					end
					if draft.workspace == "worktree" then
						table.insert(parts, labelled(items, "base_branch", "Base branch", true, "Each run gets its own git worktree; existing worktrees are never removed.", function(f)
							return input(f, "base_branch", "Base branch", "Current branch")
						end))
					end
					return parts
				end),
			}
		end))
		return out
	end)
	local settings = box(ctx, "col", "settings", "automations.formSettings", nil, function(c)
		local out = {
			text("kicker", "EXECUTION SETTINGS", "automations.kicker"),
			ui.node("col", { key = "agent", role = "automations.field" }, {
				text("label", "Agent", "automations.fieldLabel"),
				segment(c, "agentChoice", Model.AGENTS, draft.agent, "agent"),
			}),
		}
		if draft.agent ~= "command" then
			table.insert(out, labelled(c, "model", "Model", true, "Leave blank for the agent's default.", function(f)
				return input(f, "model", "Model", "Agent default")
			end))
		end
		if draft.agent == "command" then
			table.insert(out, labelled(c, "command", "Command", false, "The program and its arguments as a JSON array.", function(f)
				return input(f, "command", "Command", '["program", "argument"]')
			end))
		end
		table.insert(out, labelled(c, "precheck", "Precheck", true, "Automatic runs only, as a JSON array. Run now skips it.", function(f)
			return input(f, "precheck", "Precheck", '["program", "argument"]')
		end))
		if Model.trim(fields.precheck.text) ~= "" then
			table.insert(out, labelled(c, "precheck_timeout", "Precheck timeout", false, "Seconds.", function(f)
				return input(f, "precheck_timeout", "Precheck timeout", "60")
			end))
		end
		table.insert(out, labelled(c, "grace", "Missed-run grace", false, "Minutes a missed schedule or event may still start.", function(f)
			return input(f, "grace", "Missed-run grace", "60")
		end))
		table.insert(out, ui.node("col", { key = "permissions", role = "automations.formSection" }, {
			text("title", "Permissions", "automations.fieldLabel"),
			text("note", Model.PERMISSION_NOTE, "automations.permissionNote"),
		}))
		return out
	end)
	local editing = draft.id ~= nil
	local footer = { ui.node("row", { key = "buttons", role = "automations.actions" }, {
		button("cancel", "Cancel", "cancel", "automations.button"),
		button("save", if editing then "Save changes" else "Create automation", "save", "automations.primaryButton"),
	}) }
	if state.error then
		table.insert(footer, 1, text("error", state.error, "automations.error", { grow = 1 }))
	end
	return ui.node("col", { key = "page", role = "automations.page" }, {
		ui.node("row", { key = "nav", role = "automations.nav" }, {
			button("back", "← Automations", "cancel", "automations.backButton"),
		}),
		ui.node("row", { key = "head", role = "automations.head" }, {
			ui.node("col", { key = "titles", role = "automations.titles", grow = 1 }, {
				text("title", if editing then "Edit automation" else "New automation", "automations.title"),
				text("subtitle", "Define when your agent runs and what it should do.", "automations.secondary"),
			}),
		}),
		ui.node("col", { key = "card", role = "automations.formCard" }, {
			ui.node("row", { key = "grid", role = "automations.formGrid" }, { main, settings }),
			ui.node("row", { key = "footer", role = "automations.formFooter" }, footer),
		}),
	})
end

function View.render(state: State, now: number): BlockView
	state.ids = {}
	local root: Ctx = { path = "main", ids = state.ids }
	local draft = state.draft
	if state.mode == "editor" and draft then
		return { main = editor(root, state, draft) }
	end
	local run = if state.mode == "run" then Model.findRun(state.snapshot.runs, state.runId) else nil
	if run then
		return { main = runDetail(state, run, now) }
	end
	local definition = if state.mode == "detail" then Model.find(state.snapshot.definitions, state.selected) else nil
	if definition then
		return { main = automationDetail(state, definition, now) }
	end
	return { main = overview(root, state, now) }
end

return View
