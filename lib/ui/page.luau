--!strict
-- The page inset. Tern draws a block's root with no horizontal padding, and no native prop adds one.
-- Needs `ui/ui.css` in the plugin's manifest `styles`.
local ui = tern.ui

local Page = {}

function Page.render(children: { Node }): Node
	return ui.node("col", { key = "page", role = "tpui.page" }, children)
end

return Page
