--!strict
local Kit = require("./kit")

local ui = tern.ui
local group, node = Kit.group, Kit.node

local function chip(label: string, props: { [string]: any }?): any
	local p = props or {}
	p.head = label
	return node("card", p, { ui.text(label) })
end

local function tag(label: string, tall: boolean?): any
	return node("card", { head = label }, if tall then { ui.text("line one"), ui.text("line two"), ui.text("line three") } else { ui.text("x") })
end

local function lines(count: number, prefix: string): { any }
	local out = {}
	for i = 1, count do
		table.insert(out, ui.text(`{prefix} {i}`))
	end
	return out
end

local Layout: Kit.Section = {
	id = "layout",
	label = "Layout",
	build = function(s: Kit.State): { any }
		local gaps = {}
		for _, gap in { "none", "xs", "sm", "md", "lg" } do
			table.insert(gaps, node("row", { gap = gap }, { ui.badge(gap, "accent"), ui.badge("a", "neutral"), ui.badge("b", "neutral"), ui.badge("c", "neutral") }))
		end
		local aligns = {}
		for _, align in { "start", "center", "end", "baseline", "stretch" } do
			table.insert(aligns, node("row", { gap = "sm", align = align }, { ui.badge(align, "accent"), tag("short"), tag("tall", true) }))
		end
		return {
			group("Row and col: gap none, xs, sm, md, lg", {
				node("col", { gap = "sm" }, gaps),
				node("row", { gap = "md" }, { node("col", { gap = "none" }, { ui.badge("col", "accent"), ui.text("none"), ui.text("none") }), node("col", { gap = "lg" }, { ui.badge("col", "accent"), ui.text("lg"), ui.text("lg") }) }),
			}),
			group("Row: align", aligns),
			group("Row: justify and wrap", {
				node("row", { justify = "between" }, { ui.badge("start", "accent"), ui.badge("between", "neutral"), ui.badge("end", "accent") }),
				node("row", { justify = "end", gap = "sm" }, { ui.badge("justify", "neutral"), ui.badge("end", "accent") }),
				node("row", { wrap = true, gap = "sm" }, {
					ui.badge("wrap one", "info"), ui.badge("wrap two", "info"), ui.badge("wrap three", "info"), ui.badge("wrap four", "info"), ui.badge("wrap five", "info"), ui.badge("wrap six", "info"),
					ui.badge("wrap seven", "info"), ui.badge("wrap eight", "info"), ui.badge("wrap nine", "info"), ui.badge("wrap ten", "info"), ui.badge("wrap eleven", "info"), ui.badge("wrap twelve", "info"),
				}),
			}),
			group("Grow, basis, max, min", {
				node("row", { gap = "sm" }, { chip("grow 1", { grow = 1 }), chip("grow 2", { grow = 2 }) }),
				node("row", { gap = "sm" }, { chip("basis 0.25", { basis = 0.25 }), chip("basis 0.75", { basis = 0.75 }) }),
				node("row", { gap = "sm" }, { chip("content", { basis = "content" }), chip("grow 1", { grow = 1 }) }),
				node("row", { gap = "sm" }, { chip("max w 24ch", { max = { w = "24ch" } }), chip("min w 40ch", { min = { w = "40ch" } }) }),
				node("col", { max = { h = "2lines" } }, lines(5, "clipped line")),
			}),
			group("Spacer", {
				node("row", { gap = "none" }, { ui.badge("none", "neutral"), node("spacer", { size = "sm" }), ui.badge("sm", "neutral"), node("spacer", { size = "lg" }), ui.badge("lg", "neutral") }),
				node("row", {}, { ui.badge("pushed", "neutral"), node("spacer", { grow = 1 }), ui.badge("to the end", "accent") }),
			}),
			group("Split: hairline, gutter, tiles, col", {
				node("split", { key = "sp1", sizes = { 1, 2 }, h = "6lines" }, { ui.col({ ui.text("1 of 3") }), ui.col({ ui.text("2 of 3") }) }),
				node("split", { key = "sp2", variant = "gutter", sizes = { 1, 1 }, h = "6lines" }, { ui.col({ ui.text("Gutter") }), ui.col({ ui.text("Pane") }) }),
				node("split", { key = "sp3", variant = "tiles", sizes = { 1, 1, 1 }, h = "6lines" }, { ui.col({ ui.text("Tiles") }), ui.col({ ui.text("Pane") }), ui.col({ ui.text("Pane") }) }),
				node("split", { key = "sp4", dir = "col", sizes = { 1, 1 }, h = "10lines", min = "2lines" }, { ui.col({ ui.text("Top") }), ui.col({ ui.text("Bottom") }) }),
			}),
			group("Scroll: bar, fade, stick end", {
				node("scroll", { key = "sc1", max = { h = "4lines" } }, lines(12, "scroll line")),
				node("scroll", { key = "sc2", variant = "fade", max = { h = "4lines" }, noun = "line" }, lines(12, "fade line")),
				node("scroll", { key = "sc3", stick = "end", max = { h = "4lines" }, noun = { "entry", "entries" } }, lines(12, "log entry")),
			}),
		}
	end,
}

return Layout
