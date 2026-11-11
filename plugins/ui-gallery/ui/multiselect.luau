--!strict
-- Multi selector: picked options as chips plus a native `menu` of checked rows; a chip sends {ev="action", act=<name>, value=<id>}, a menu row {ev="action", id=<...name.menu>, act=<id>, checked=<bool>}; flip with Checkbox.flip.
local Checkbox = require("./checkbox")

local ui = tern.ui

local MultiSelect = {}

function MultiSelect.render(name: string, options: { Checkbox.Option }, picked: { string }, text: string?): Node
	local on: { [string]: boolean } = {}
	for _, id in picked do
		on[id] = true
	end
	local children = {}
	local items = {}
	for _, o in options do
		local checked = on[o.id] == true
		if checked then
			table.insert(children, ui.button(o.label, { key = o.id, size = "sm", icon = "x", title = "Remove", actions = { click = `{name}={o.id}` } }))
		end
		table.insert(items, { id = o.id, label = o.label, checked = checked, disabled = o.disabled })
	end
	table.insert(children, ui.node("menu", { key = "menu", text = text or "Add", icon = "plus", size = "sm", variant = "dense", items = items }))
	return ui.node("row", { key = name, gap = "xs", wrap = true }, children)
end

function MultiSelect.pick(ev: UiEvent, name: string): string?
	if ev.ev ~= "action" then
		return nil
	end
	if ev.act == name and type(ev.value) == "string" then
		return ev.value
	end
	local suffix = `.{name}.menu`
	if type(ev.id) == "string" and type(ev.act) == "string" and string.sub(ev.id, -#suffix) == suffix then
		return ev.act
	end
	return nil
end

return MultiSelect
