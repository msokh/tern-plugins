--!strict
local Kit = require("./kit")
local Chat = require("./chat")
local Container = require("./container")
local Content = require("./content")
local Layout = require("./layout")
local Page = require("./ui/page")
local Checkbox = require("./ui/checkbox")
local Radio = require("./ui/radio")
local MultiSelect = require("./ui/multiselect")

local ui = tern.ui

type State = Kit.State

local group, node, val, bound, at = Kit.group, Kit.node, Kit.val, Kit.bound, Kit.at

local CHANNELS: { Checkbox.Option } = { { id = "email", label = "Email", detail = "On every failure" }, { id = "slack", label = "Slack" }, { id = "hook", label = "Webhook", disabled = true } }
local SCHEDULES: { Checkbox.Option } = { { id = "daily", label = "Daily" }, { id = "weekly", label = "Weekly", detail = "Mondays at 03:00" }, { id = "monthly", label = "Monthly", disabled = true } }
local LABELS: { Checkbox.Option } = { { id = "bug", label = "Bug" }, { id = "docs", label = "Docs" }, { id = "perf", label = "Perf" } }
local DEFAULTS = { cb_one = { "terms" }, cb_list = { "slack" }, radio = "weekly", msel = { "bug", "docs" } }

local SELECT_OPTIONS = {
	{ value = "sonnet", label = "Sonnet 4.5", detail = "$3 / $15" },
	{ value = "opus", label = "Opus 4.1", detail = "$15 / $75" },
	{ value = "haiku", label = "Haiku 4.5", detail = "$1 / $5", group = "Fast" },
}

local MENU_ITEMS = {
	{ id = "open", label = "Open", icon = "folder", keys = { "cmd", "o" } },
	{ id = "dup", label = "Duplicate", detail = "Copy with its schedule" },
	"-",
	{ header = "View" },
	{ id = "compact", label = "Compact", checked = true },
	{ id = "asc", label = "Ascending", radio = "sort", checked = true },
	{ id = "desc", label = "Descending", radio = "sort" },
	"-",
	{ id = "del", label = "Delete", danger = true, icon = "trash" },
}

local MENUBAR_VIEW = {
	{ id = "zoom", label = "Zoom in", keys = { "cmd", "+" } },
	{ id = "export", label = "Export", icon = "open", items = { { id = "json", label = "JSON" }, { id = "csv", label = "CSV" } } },
	"-",
	{ id = "sidebar", label = "Sidebar", checked = true },
}

local TYPEAHEAD = {
	{ value = "sonnet", label = "Sonnet 4.5", detail = "$3 / $15", icon = "provider:anthropic", group = "Anthropic" },
	{ value = "opus", label = "Opus 4.1", detail = "$15 / $75", icon = "provider:anthropic", group = "Anthropic" },
	{ value = "codex", label = "GPT-5 Codex", detail = "$1.25 / $10", icon = "provider:openai", group = "OpenAI" },
	{ value = "o3", label = "o3", detail = "retired", icon = "provider:openai", group = "OpenAI", disabled = true },
}

local HOVER_CARD = ui.col({
	ui.text({ ui.span("Frozen lockfile", "strong") }),
	ui.text({ ui.span("CI fails when the lockfile needs an update.", "muted") }),
	ui.kv({ { "fix", "pnpm install" }, { "seen", "3 runs" } }),
})

local POPOVER_ANCHOR = at("Open an overlay", "btns", "pop")

local PALETTE = {
	{ id = "review", label = "Review changes", icon = "diff", detail = "the working tree", facts = { keys = "⌘R" }, hits = { { 0, 2 } } },
	{ id = "revert", label = "Revert last edit", icon = "undo", facts = { keys = "⌘Z" }, hits = { { 0, 2 } } },
	{ id = "rename", label = "Rename session", icon = "pen", facts = { keys = "F2" }, hits = { { 0, 2 } } },
	{ id = "restart", label = "Restart agent", icon = "repeat", hits = { { 0, 2 } } },
	{ id = "resume", label = "Resume a session", icon = "history", detail = "from the list", hits = { { 0, 2 } } },
}

local PALETTE_ORDER = { { group = "review", label = "Review", count = 2 }, "review", "revert", { group = "session", label = "Session", count = 3 }, "rename", "restart", "resume" }

local sections = {
	{
		id = "action",
		label = "Action",
		build = function(s: State): { any }
			return {
				group("Button", {
					ui.row({ ui.button("Default"), ui.button("Primary", { variant = "primary" }), ui.button("Quiet", { variant = "quiet" }), ui.button("Danger", { variant = "danger" }) }),
					ui.row({ ui.button("Default", { size = "sm" }), ui.button("Primary", { variant = "primary", size = "sm" }), ui.button("Quiet", { variant = "quiet", size = "sm" }), ui.button("Danger", { variant = "danger", size = "sm" }) }),
				}),
				group("States", {
					ui.row({
						ui.button("With icon", { icon = "plus" }),
						ui.button("On", { on = true }),
						ui.button("Disabled", { disabled = true }),
						ui.button("Disabled, reason", { disabled = "Nothing to run" }),
						ui.button("Busy", { busy = true }),
						ui.button("Keys", { keys = { "cmd", "k" } }),
					}),
				}),
				group("Icon button", {
					ui.row({
						ui.button("", { icon = "refresh", title = "Refresh" }),
						ui.button("", { icon = "refresh", variant = "quiet", title = "Refresh" }),
						ui.button("", { icon = "trash", variant = "danger", title = "Delete" }),
						ui.button("", { icon = "refresh", size = "sm", title = "Refresh" }),
						ui.button("", { icon = "refresh", on = true, title = "Refresh" }),
					}),
				}),
				group("Button group, split, toolbar", {
					node("buttons", { variant = "joined" }, { ui.button("Copy"), ui.button("Cut"), ui.button("Paste") }),
					node("buttons", { variant = "split" }, { ui.button("Save", { variant = "primary" }), ui.button("", { icon = "chev", variant = "primary", title = "More" }) }),
					node("buttons", { variant = "toolbar" }, { ui.button("", { icon = "search", title = "Find" }), ui.button("", { icon = "list", on = true, title = "Outline" }), ui.button("", { icon = "refresh", title = "Refresh" }) }),
				}),
				group("Segmented control", {
					bound(s, "tabs", "seg", { variant = "segmented", active = val(s, "seg", "grid"), items = { { id = "grid", label = "Grid" }, { id = "list", label = "List" }, { id = "table", label = "Table" } } }),
				}),
				group("Toggle button group", {
					node("buttons", { variant = "joined" }, {
						ui.button("List", { on = val(s, "tg", "list") == "list", actions = { click = "tg=list" } }),
						ui.button("Grid", { on = val(s, "tg", "list") == "grid", actions = { click = "tg=grid" } }),
						ui.button("Board", { on = val(s, "tg", "list") == "board", actions = { click = "tg=board" } }),
					}),
				}),
				group("Menu (dropdown, more)", {
					ui.row({
						bound(s, "menu", "m1", { text = "Actions", caret = true, items = MENU_ITEMS }),
						bound(s, "menu", "m2", { icon = "more", title = "More", trigger = "quiet", items = MENU_ITEMS }),
						bound(s, "menu", "m3", { text = "Dense", variant = "dense", items = MENU_ITEMS }),
					}),
				}),
				group("Link", { ui.text({ ui.link("Documentation", "https://example.com"), ui.span("  "), ui.path("~/notes.md") }) }),
			}
		end,
	},
	{
		id = "form",
		label = "Form",
		build = function(s: State): { any }
			return {
				group("Input default vs field", {
					node("input", { key = "i1", text = "", placeholder = "Search automations" }),
					node("input", { key = "i2", text = "", placeholder = "Search automations", variant = "field", icon = "search" }),
					node("input", { key = "i3", text = "Nightly review", variant = "field", clear = true }),
					node("input", { key = "i4", text = val(s, "i4", "42"), variant = "field", stepper = true, unit = "min", role = "gallery.number" }),
					node("input", { key = "i5", text = "hunter2", variant = "field", secret = true }),
					node("input", { key = "i6", text = "example.com", variant = "field", prefix = "https://", suffix = ".org" }),
				}),
				group("Field", {
					node("field", { label = "Name", hint = "Shown in the list", required = true, variant = "stacked" }, { node("input", { key = "f1", text = "Nightly", variant = "field" }) }),
					node("field", { label = "Cron", error = "Five fields expected", variant = "grid" }, { node("input", { key = "f2", text = "0 3 *", variant = "field" }) }),
					node("field", { label = "Retries", warning = "Above the default", variant = "grid" }, { node("input", { key = "f3", text = "9", variant = "field" }) }),
					node("field", { label = "Notify", hint = "Email on failure", variant = "row" }, { node("switch", { key = "f4", on = true }) }),
				}),
				group("Empty", {
					node("empty", { title = "No automations", text = "Create one to run an agent on a schedule." }, { ui.button("New automation", { variant = "primary" }) }),
					node("empty", { variant = "inline", title = "No hits", text = "Clear the filter" }),
					node("empty", { variant = "drop", title = "Drop a file", text = "or browse" }),
				}),
				group("Split", { node("split", { key = "sp", sizes = { 1, 1 }, h = "8lines" }, { ui.col({ ui.text("Task") }), ui.col({ ui.text("Execution") }) }) }),
			}
		end,
	},
	{
		id = "controls",
		label = "Form Controls",
		build = function(s: State): { any }
			return {
				group("Select (field, quiet, search, disabled)", {
					ui.row({
						bound(s, "select", "sel1", { value = val(s, "sel1", "sonnet"), options = SELECT_OPTIONS, open = val(s, "sel1_open", false) }),
						bound(s, "select", "sel2", { variant = "quiet", label = "Model", value = val(s, "sel2", "opus"), options = SELECT_OPTIONS, open = val(s, "sel2_open", false) }),
						bound(s, "select", "sel3", { options = SELECT_OPTIONS, placeholder = "Choose a model", size = "sm" }),
						bound(s, "select", "sel4", { value = "haiku", options = SELECT_OPTIONS, disabled = "Locked" }),
					}),
					bound(s, "select", "sel5", { search = true, value = val(s, "sel5", "sonnet"), options = TYPEAHEAD, query = "o", total = 24, open = val(s, "sel5_open", false), role = "gallery.typeahead" }),
				}),
				group("Switch", {
					bound(s, "switch", "sw1", { label = "Notifications", hint = "Email when a run fails", on = val(s, "sw1", true) }),
					bound(s, "switch", "sw2", { variant = "compact", label = "Compact", on = val(s, "sw2", false) }),
					bound(s, "switch", "sw3", { variant = "segment", label = "Mode", on = val(s, "sw3", false) }),
					bound(s, "switch", "sw4", { label = "Locked", on = true, disabled = "Managed by policy" }),
				}),
				group("Slider", {
					bound(s, "slider", "sl1", { label = "Opacity", min = 0, max = 100, value = val(s, "sl1", 40), unit = "%" }),
					bound(s, "slider", "sl2", { variant = "accent", label = "Temperature", min = 0, max = 1, step = 0.1, value = val(s, "sl2", 0.6) }),
					bound(s, "slider", "sl3", { label = "Window", min = 0, max = 2000, format = "duration", value = { 200, 1200 } }),
				}),
				group("Checkbox, radio list, multi selector (lib/ui)", {
					Checkbox.render("cb_one", { { id = "terms", label = "Accept the terms" } }, val(s, "cb_one", DEFAULTS.cb_one)),
					Checkbox.render("cb_list", CHANNELS, val(s, "cb_list", DEFAULTS.cb_list)),
					Radio.render("radio", SCHEDULES, val(s, "radio", DEFAULTS.radio)),
					MultiSelect.render("msel", LABELS, val(s, "msel", DEFAULTS.msel), "Labels"),
					node("spacer", { size = "lg" }),
				}),
				group("Date and calendar", {
					ui.row({
						bound(s, "calendar", "cal1", { value = val(s, "cal1", "2026-11-11"), month = "2026-11", today = "2026-11-11", marks = { "2026-11-04", { date = "2026-11-18", tone = "warning" } } }),
						bound(s, "calendar", "cal2", { range = true, value = { "2026-11-03", "2026-11-07" }, month = "2026-11", today = "2026-11-11" }),
					}),
					bound(s, "calendar", "cal3", { variant = "week", presets = { { id = "today", label = "Today" }, { id = "7", label = "Last 7 days" } }, preset = val(s, "cal3_p", "7"), value = { "2026-11-05", "2026-11-11" }, today = "2026-11-11" }),
					ui.row({
						bound(s, "date", "d1", { value = val(s, "d1", "2026-11-11"), open = val(s, "d1_open", false), today = "2026-11-11" }),
						bound(s, "date", "d2", { range = true, placeholder = "Pick dates", month = "2026-11", today = "2026-11-11", role = "gallery.daterange" }),
					}),
				}),
				group("OTP", {
					bound(s, "otp", "o1", { text = "481", length = 6 }),
					bound(s, "otp", "o2", { variant = "joined", text = "481927", state = "success", hint = "Verified" }),
					bound(s, "otp", "o3", { variant = "underline", text = "48", state = "error", hint = "That code didn't work" }),
				}),
				group("Text area / editor", {
					node("editor", { key = "ed1", text = "Line one\nLine two", variant = "field", placeholder = "Message" }),
					node("editor", { key = "ed2", text = "", variant = "field", placeholder = "Ask something", buttons = { { act = "send", icon = "arrow-up", variant = "primary", title = "Send" } } }),
				}),
			}
		end,
	},
	{
		id = "feedback",
		label = "Feedback & Status",
		build = function(s: State): { any }
			local rows = {}
			for _, tone in { "neutral", "accent", "info", "success", "warning", "error", "pending", "muted" } do
				table.insert(rows, ui.row({ ui.badge(tone, tone), node("icon", { name = "success", tone = tone }), node("spinner", { style = "dots", tone = tone }), node("progress", { value = 0.6, tone = tone, grow = 1 }) }))
			end
			return {
				group("Badge, status dot, spinner, progress by tone", rows),
				group("Progress", { ui.progress(0.4, "40%"), ui.progress(nil, "Preparing"), node("meter", { style = "ring", value = 0.7, label = "70%" }), node("meter", { style = "blocks", value = 0.5, steps = 10 }) }),
				group("Spinner styles", { ui.row({ node("spinner", { style = "braille", label = "braille" }), node("spinner", { style = "starburst", label = "starburst" }), node("spinner", { style = "orbit", label = "orbit" }) }) }),
				group("Skeleton", { node("skeleton", { shape = "text", lines = 2 }), node("skeleton", { shape = "avatar" }), node("skeleton", { shape = "rows", rows = 2, variant = "pulse" }) }),
				group("Banner (card with tone)", { node("card", { head = "Heads up", tone = "warning", icon = "warn" }, { ui.text("Runs are paused until you resume them.") }) }),
				group("Info tip (tooltip, hover card)", {
					ui.row({
						ui.text({ ui.span("Tooltip", "muted") }),
						node("icon", { name = "info", title = "Runs again when the lockfile changes", role = "gallery.infotip" }),
						ui.text({ ui.span("Hover card", "muted") }),
						node("icon", { name = "help", hovercard = HOVER_CARD, role = "gallery.infocard" }),
					}),
				}),
				group("Table dot cells", { ui.table({ { id = "n", head = "Run" }, { id = "s", head = "State" } }, { { id = "a", cells = { { "nightly" }, { text = "ok", dot = "success" } } }, { id = "b", cells = { { "weekly" }, { text = "failed", dot = "error" } } } }) }),
			}
		end,
	},
	{
		id = "navigation",
		label = "Navigation",
		build = function(s: State): { any }
			return {
				group("Tabs (underline, segmented)", {
					bound(s, "tabs", "tb1", { variant = "underline", active = val(s, "tb1", "a"), items = { { id = "a", label = "Overview" }, { id = "b", label = "Runs" }, { id = "c", label = "Settings" } } }),
					bound(s, "tabs", "tb2", { variant = "segmented", active = val(s, "tb2", "a"), items = { { id = "a", label = "All" }, { id = "b", label = "Paused" } } }),
				}),
				group("Breadcrumb", {
					bound(s, "breadcrumb", "bc1", { items = { { id = "home", label = "Home", icon = "home" }, { id = "auto", label = "Automations" }, { id = "run", label = "Nightly" } } }),
					bound(s, "breadcrumb", "bc2", { variant = "path", items = { { id = "a", label = "src" }, { id = "b", label = "lib" }, { id = "c", label = "ui.luau" } } }),
				}),
				group("Pager", {
					bound(s, "pager", "pg1", { variant = "range", page = val(s, "pg1", 2), total = 312, size = 12 }),
					bound(s, "pager", "pg2", { variant = "pages", page = val(s, "pg2", 3), pages = 26 }),
					bound(s, "pager", "pg3", { variant = "more", page = 1, total = 312, size = 50, label = "commits" }),
				}),
				group("Nav (side, top)", {
					bound(s, "nav", "nv1", { role = "gallery.navpills", active = val(s, "nv1", "a"), items = { { id = "a", label = "Overview", icon = "home" }, { id = "b", label = "Runs", count = 12 }, { id = "c", label = "More", items = { { id = "c1", label = "Settings" }, { id = "c2", label = "Billing" } } } } }),
					bound(s, "nav", "nv2", {
						role = "gallery.meganav",
						variant = "links",
						active = val(s, "nv2", "a"),
						items = {
							{ id = "a", label = "Docs" },
							{ id = "prod", label = "Products", items = { { id = "p1", label = "Atlas", detail = "Map every service", icon = "globe" }, { id = "p2", label = "Relay", detail = "Route events between teams", icon = "broadcast" }, { id = "p3", label = "Ledger", detail = "Every release, with rollbacks", icon = "history" }, { id = "p4", label = "Probe", detail = "Checks before a promote", icon = "bolt" } } },
							{ id = "b", label = "Blog" },
						},
					}),
				}),
				group("Menubar", {
					node("menubar", { key = "mb", role = "gallery.menubar", icon = "terminal", menus = { { id = "file", label = "File", items = { { id = "new", label = "New" }, { id = "quit", label = "Quit" } } }, { id = "view", label = "View", items = MENUBAR_VIEW } } }),
				}),
				group("Stepper (row of badges)", { ui.row({ ui.badge("1 Plan", "success"), ui.text("›"), ui.badge("2 Build", "accent"), ui.text("›"), ui.badge("3 Ship", "muted") }) }),
			}
		end,
	},
	{
		id = "table",
		label = "Table & List",
		build = function(s: State): { any }
			local rows = {}
			for _, r in { { "a", "nightly", "ok", "success" }, { "b", "weekly", "failed", "error" }, { "c", "hourly", "running", "pending" } } do
				table.insert(rows, { id = r[1], cells = { n = r[2], s = { text = r[3], dot = r[4] }, m = { meter = { value = 0.4 } } } })
			end
			return {
				group("Table (selectable, sortable, multi)", {
					bound(s, "table", "t1", { selectable = true, selected = val(s, "t1", "b"), sort = { col = "n", dir = "asc" }, cols = { { id = "n", head = "Name", grow = 1, sortable = true }, { id = "s", head = "State" }, { id = "m", head = "Load" } }, rows = rows }),
					bound(s, "table", "t2", { multi = true, picked = val(s, "t2", { "a" }), cols = { { id = "n", head = "Name", grow = 1 }, { id = "s", head = "State" } }, rows = rows, bar = { { act = "stop", text = "Stop" } } }),
				}),
				group("List", {
					bound(s, "list", "ls1", { selected = val(s, "ls1", nil), max = { lines = 6 } }, {
						node("item", { key = "x", label = "main", detail = "origin/main", value = "up 2", icon = "git-branch" }),
						node("item", { key = "y", label = "fix-login", detail = "no upstream", icon = "git-branch", tone = "warning" }),
						node("item", { key = "z", label = "locked", disabled = true }),
					}),
				}),
				group("Metadata list (kv), stats", {
					ui.kv({ { "context", "prod" }, { "namespace", "default" } }),
					ui.stats({ { label = "Runs", value = "24", sub = "2 failed" }, { label = "p95", value = "182 ms", tone = "warning" } }),
				}),
				group("Tree", { ui.tree({ { label = "src", icon = "folder", open = true, children = { { label = "main.rs", icon = "file" }, { label = "lib", icon = "folder", children = { { label = "ui.rs" } } } } } }) }),
				group("Overflow list (breadcrumb max)", { node("breadcrumb", { key = "of", max = 3, items = { { id = "1", label = "a" }, { id = "2", label = "b" }, { id = "3", label = "c" }, { id = "4", label = "d" }, { id = "5", label = "e" } } }) }),
			}
		end,
	},
	{
		id = "overlay",
		label = "Overlay",
		build = function(s: State): { any }
			return {
				group("Open an overlay", {
					node("row", { key = "btns", gap = "sm" }, {
						ui.button("Dialog", { actions = { click = "ov=dialog" } }),
						ui.button("Drawer", { actions = { click = "ov=drawer" } }),
						ui.button("Sheet", { actions = { click = "ov=sheet" } }),
						ui.button("Toast", { actions = { click = "ov=toast" } }),
						ui.button("Popover", { key = "pop", actions = { click = "ov=popover" } }),
						ui.button("Palette", { actions = { click = "ov=palette" } }),
					}),
					ui.text({ ui.span("open: ", "muted"), ui.span(val(s, "ov", "none"), "strong") }),
				}),
				group("Tooltip and hover card", {
					node("row", { key = "tips", gap = "sm" }, {
						ui.button("Tooltip", { role = "gallery.tooltip", title = "Runs the automation now" }),
						ui.button("Hover card", { role = "gallery.hovercard", hovercard = HOVER_CARD }),
					}),
				}),
			}
		end,
		layer = function(s: State): any?
			local which = val(s, "ov", "none")
			local close = ui.button("Close", { key = "end", variant = "quiet", actions = { click = "ov=none" } })
			if which == "dialog" then
				return node("overlay", { key = "dlg", head = "Delete automation", modal = true, ["end"] = "layer.dlg.end", foot = "layer.dlg.foot" }, {
					close,
					ui.text("This cannot be undone."),
					node("row", { key = "foot", gap = "sm", justify = "end" }, { ui.button("Cancel", { actions = { click = "ov=none" } }), ui.button("Delete", { variant = "danger", actions = { click = "ov=none" } }) }),
				})
			elseif which == "drawer" then
				return node("overlay", { key = "drw", head = "Details", side = "right", modal = true, ["end"] = "layer.drw.end" }, { close, ui.text("Right-side sheet.") })
			elseif which == "sheet" then
				return node("overlay", { key = "sht", head = "Details", side = "bottom", ["end"] = "layer.sht.end" }, { close, ui.text("Bottom drawer.") })
			elseif which == "popover" then
				return node("overlay", { key = "pop", head = "Schedule", anchor = { node = POPOVER_ANCHOR, side = "below" }, ["end"] = "layer.pop.end" }, {
					close,
					ui.kv({ { "runs", "Every night at 03:00" }, { "next", "Tomorrow" } }),
					node("switch", { key = "pop_weekends", label = "Skip weekends", on = val(s, "pop_weekends", false) }),
				})
			elseif which == "palette" then
				return node("picker", {
					key = "pal",
					size = "md",
					title = "Commands",
					icon = "search",
					query = "re",
					placeholder = "Type a command",
					noun = "commands",
					total = 28,
					items = PALETTE,
					order = PALETTE_ORDER,
					selected = val(s, "pal", "review"),
					columns = { { id = "keys", head = "Keys", format = "dim" } },
					actions = { { id = "close", label = "Close", keys = { "esc" } }, { id = "run", label = "Run", primary = true, keys = { "enter" } } },
				})
			end
			return nil
		end,
	},
	Chat,
	Container,
	Content,
	Layout,
}

local function swatch(from: string, to: string, label: string): string
	return `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="200" viewBox="0 0 320 200"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{from}"/><stop offset="1" stop-color="{to}"/></linearGradient></defs><rect width="320" height="200" fill="url(#g)"/><text x="16" y="110" font-size="28" fill="white" font-family="sans-serif">{label}</text></svg>`
end

tern.block.define("gallery", {
	font = "sans",
	init = function(cx: BlockCx): State
		local img = {
			cx:blob(swatch("#4f8cff", "#9b5cff", "one"), "image/svg+xml"),
			cx:blob(swatch("#ff8a4f", "#ff4f8c", "two"), "image/svg+xml"),
			cx:blob(swatch("#2fbf71", "#1f8fbf", "three"), "image/svg+xml"),
		}
		return { tab = "action", last = "", v = {}, img = img }
	end,
	view = function(state: State)
		local items = {}
		local body: { any } = {}
		local layer = nil
		for _, section in sections do
			table.insert(items, { id = section.id, label = section.label })
			if section.id == state.tab then
				body = section.build(state)
				local make = (section :: any).layer
				if make then
					layer = make(state)
				end
			end
		end
		return {
			main = ui.col({
				node("tabs", { key = "tabs", variant = "underline", active = state.tab, items = items }),
				Page.render({
					node("col", { key = "body", gap = "sm", max = { w = "110ch" } }, body),
					ui.text({ ui.span("last event: ", "muted"), ui.span(state.last, "muted") }),
				}),
			}),
			layer = if layer then ui.col({ layer }) else nil,
		}
	end,
	event = function(state: State, ev: UiEvent, cx: BlockCx)
		local name: string? = if ev.id then (string.match(ev.id :: string, "([^%.]+)$") :: string?) else nil
		local one = Checkbox.pick(ev, "cb_one")
		local many = Checkbox.pick(ev, "cb_list")
		local radio = Radio.pick(ev, "radio")
		local multi = MultiSelect.pick(ev, "msel")
		if one then
			state.v.cb_one = Checkbox.flip(val(state, "cb_one", DEFAULTS.cb_one), one)
		elseif many then
			state.v.cb_list = Checkbox.flip(val(state, "cb_list", DEFAULTS.cb_list), many)
		elseif radio then
			state.v.radio = radio
		elseif multi then
			state.v.msel = Checkbox.flip(val(state, "msel", DEFAULTS.msel), multi)
		elseif ev.ev == "select" and ev.id == "main.tabs" then
			state.tab = ev.item
		elseif name and ev.ev == "select" then
			state.v[name] = ev.item
		elseif ev.ev == "change" and name and type(ev.on) == "boolean" and type(ev.value) == "string" then
			state.v[`react.{name}.{ev.value}`] = ev.on
		elseif name and ev.ev == "change" then
			state.v[name] = ev.value
		elseif name and ev.ev == "toggle" then
			state.v[name .. "_open"] = if ev.open ~= nil then ev.open else not ev.collapsed
		elseif ev.ev == "action" and name == "i4" and (ev.act == "inc" or ev.act == "dec") then
			state.v.i4 = tostring((tonumber(val(state, "i4", "42")) or 0) + (if ev.act == "inc" then 5 else -5))
		elseif ev.ev == "action" and name == "pal" and (ev.act == "close" or ev.act == "run") then
			state.v.ov = "none"
		elseif ev.ev == "action" and ev.act and ev.value ~= nil then
			state.v[ev.act :: string] = ev.value
			if ev.act == "ov" and ev.value == "toast" then
				cx:toast("success", "Saved", "a toast from the gallery block")
			end
		end
		state.last = tern.json.encode(ev)
	end,
})
