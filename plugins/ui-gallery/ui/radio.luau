--!strict
-- Radio list from native `meter` rings and `text`; a click sends {ev="action", act=<name>, value=<option id>}; keep the last value.
local Checkbox = require("./checkbox")

local ui = tern.ui

local Radio = {}

function Radio.render(name: string, options: { Checkbox.Option }, value: string?): Node
	local rows = {}
	for _, o in options do
		local on = o.id == value
		local spans: { any } = { ui.span(o.label, if o.disabled == true then "muted" else nil) }
		if o.detail then
			table.insert(spans, ui.span("  " .. o.detail, "muted"))
		end
		table.insert(
			rows,
			ui.node("row", { key = o.id, gap = "sm", actions = if o.disabled == true then nil else { click = `{name}={o.id}` } }, {
				ui.node("meter", { style = "ring", size = "md", value = if on then 1 else 0 }),
				ui.text(spans),
			})
		)
	end
	return ui.node("col", { key = name, gap = "sm" }, rows)
end

function Radio.pick(ev: UiEvent, name: string): string?
	return Checkbox.pick(ev, name)
end

return Radio
