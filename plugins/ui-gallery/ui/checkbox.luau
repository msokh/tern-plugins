--!strict
-- Checkbox list from a native `list` of `item` rows; a click sends {ev="action", act=<name>, value=<option id>}; flip `picked` with Checkbox.flip.
local ui = tern.ui

export type Option = { id: string, label: string, detail: string?, disabled: boolean? }

local Checkbox = {}

function Checkbox.render(name: string, options: { Option }, picked: { string }): Node
	local on: { [string]: boolean } = {}
	for _, id in picked do
		on[id] = true
	end
	local rows = {}
	for _, o in options do
		local checked = on[o.id] == true
		table.insert(
			rows,
			ui.node("item", {
				key = o.id,
				label = o.label,
				detail = o.detail,
				disabled = o.disabled,
				icon = if checked then "check" else "selection",
				tone = if checked then "accent" else nil,
				actions = { click = `{name}={o.id}` },
			})
		)
	end
	return ui.node("list", { key = name }, rows)
end

function Checkbox.pick(ev: UiEvent, name: string): string?
	if ev.ev == "action" and ev.act == name and type(ev.value) == "string" then
		return ev.value
	end
	return nil
end

function Checkbox.flip(picked: { string }, id: string): { string }
	local out = {}
	local found = false
	for _, p in picked do
		if p == id then
			found = true
		else
			table.insert(out, p)
		end
	end
	if not found then
		table.insert(out, id)
	end
	return out
end

return Checkbox
