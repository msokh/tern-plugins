--!strict
local ui = tern.ui

export type State = { tab: string, last: string, v: { [string]: any }, img: { string } }

-- A section is one tab. `layer` draws the overlay region while the tab is open.
export type Section = { id: string, label: string, build: (State) -> { any }, layer: ((State) -> any?)? }

local Kit = {}

function Kit.node(kind: string, props: { [string]: any }, children: { any }?): any
	return ui.node(kind, props, children)
end

function Kit.slug(title: string): string
	return (string.lower(title):gsub("[^%w]+", "_"))
end

-- A card whose key is its title, so a child can name a sibling's id (`Kit.at`).
function Kit.group(title: string, children: { any }): any
	return ui.card(title, children, { key = Kit.slug(title) })
end

-- The id of a node under a group of the open tab: group title, then the keys down to it.
function Kit.at(title: string, ...: string): string
	local id = "main.body." .. Kit.slug(title)
	for _, key in { ... } do
		id ..= "." .. key
	end
	return id
end

-- A controlled node: its key names its value in state.v, and the block's event() writes the user's pick back.
function Kit.val(s: State, name: string, default: any): any
	local v = s.v[name]
	if v == nil then
		return default
	end
	return v
end

function Kit.bound(s: State, kind: string, name: string, props: { [string]: any }, children: { any }?): any
	props.key = name
	return Kit.node(kind, props, children)
end

return Kit
