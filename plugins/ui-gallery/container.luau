--!strict
local Kit = require("./kit")

local ui = tern.ui
local group, node, at, val, bound = Kit.group, Kit.node, Kit.at, Kit.val, Kit.bound

local HEAD = "Card: head, icon, meta, end child"
local PICK = "Clickable and selectable card"

local LONG = "Each run writes its output here. The head folds the card, and a preview keeps the first lines visible while it is folded. "
	.. "Long bodies stay readable because the fold never loses the head.\nSecond paragraph of the same body.\nThird line."

local function tone(name: string, status: string?): any
	return node("card", { head = name, tone = name, status = status, basis = 0.48, grow = 1 }, { ui.text("Body") })
end

local function pickable(s: Kit.State, id: string, head: string, line: string): any
	local picked = val(s, "pick", "a") == id
	return node("card", { key = id, head = head, selected = picked, icon = if picked then "check" else nil, actions = { click = `pick={id}` }, basis = 0.3, grow = 1 }, { ui.text(line) })
end

local Container: Kit.Section = {
	id = "container",
	label = "Container",
	build = function(s: Kit.State): { any }
		local slides = {
			node("image", { blob = s.img[1], alt = "Render one", title = "Render one" }),
			node("image", { blob = s.img[2], alt = "Render two", title = "Render two" }),
			node("image", { blob = s.img[3], alt = "Render three", title = "Render three" }),
		}
		return {
			group(HEAD, {
				node("card", { key = "c1", icon = "server", head = "Services", meta = "24 · 2 degraded", ["end"] = at(HEAD, "c1", "end") }, {
					node("row", { key = "end", gap = "sm" }, {
						bound(s, "tabs", "cardtab", { variant = "segmented", active = val(s, "cardtab", "all"), items = { { id = "all", label = "All" }, { id = "degraded", label = "Degraded" } } }),
						ui.button("Refresh", { icon = "redo" }),
					}),
					ui.text({ ui.span("api-gateway, billing, search and 21 more", "muted") }),
				}),
				node("card", { key = "c2", head = "Notes", meta = "no icon: the body lines up with the head" }, { ui.text("Body text starts under the head text.") }),
				node("card", { key = "c3" }, { ui.text("No head: the head row is hidden and the body takes even padding.") }),
			}),
			group("Card: tones and status chips", {
				node("row", { gap = "sm", wrap = true }, {
					node("card", { head = "untoned", status = "running", basis = 0.48, grow = 1 }, { ui.text("Body") }),
					tone("neutral"),
					tone("accent"),
					tone("info"),
					tone("success", "done"),
					tone("warning"),
					tone("error", "error"),
					tone("pending", "pending"),
					tone("muted", "cancelled"),
					tone("user"),
				}),
			}),
			group("Card: collapsible, preview, inset, bare", {
				node("card", { key = "col1", head = "Collapsible, open", icon = "list", collapsible = true }, { ui.text(LONG) }),
				node("card", { key = "col2", head = "Collapsible, collapsed", icon = "list", collapsible = true, collapsed = true }, { ui.text(LONG) }),
				node("card", { key = "col3", head = "Collapsed with a 2-line preview", icon = "list", collapsible = true, collapsed = true, preview = { lines = 2 } }, { ui.text(LONG) }),
				node("card", { key = "col4", head = "src/lib.rs", icon = "file", inset = true }, { ui.code("fn main() {\n    println!(\"hi\");\n}", "rust", 1) }),
				node("card", { key = "col5", head = "Bare: no ring, fill or rounding", variant = "bare" }, { ui.text("A group of rows, or one file inside a larger card.") }),
			}),
			group("Section", {
				ui.section("Section (builder)", { ui.text("A lighter disclosure group than a card.") }),
				node("section", { key = "sec1", head = "Collapsible, open", collapsible = true }, { ui.text("Body of an open section.") }),
				node("section", { key = "sec2", head = "Collapsible, collapsed", collapsible = true, collapsed = true }, { ui.text("Hidden until the head is clicked.") }),
			}),
			group("Carousel: peek, arrows, strip", {
				bound(s, "carousel", "car1", { index = val(s, "car1", 0), h = "8lines" }, slides),
				bound(s, "carousel", "car2", { variant = "arrows", index = val(s, "car2", 0), loop = true, h = "8lines" }, {
					node("image", { blob = s.img[1], alt = "Render one" }),
					node("card", { head = "A card slide" }, { ui.text("Any node can be a slide.") }),
					node("md", { text = "### A note slide\nMarkdown works too." }),
				}),
				bound(s, "carousel", "car3", { variant = "strip", index = val(s, "car3", 1), h = "8lines" }, {
					node("image", { blob = s.img[1], alt = "Render one" }),
					node("image", { blob = s.img[2], alt = "Render two" }),
					node("image", { blob = s.img[3], alt = "Render three" }),
				}),
			}),
			group(PICK, {
				node("row", { gap = "sm", wrap = true }, {
					pickable(s, "a", "Plan A", "Ship the fix"),
					pickable(s, "b", "Plan B", "Revert first"),
					pickable(s, "c", "Plan C", "Wait a day"),
				}),
				ui.text({ ui.span("picked: ", "muted"), ui.span(val(s, "pick", "a"), "strong") }),
			}),
		}
	end,
}

return Container
