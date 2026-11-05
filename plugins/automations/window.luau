--!strict
local files = require("./files")

local KIND = "automations.manager"

local function openManager(cx: WindowCx, args: { string })
	for _, pane in cx.session:panes() do
		if pane.block == KIND and #args == 0 then
			cx.layout:focus(pane.pane)
			return
		end
	end
	cx:new_block(KIND, args, "tab")
end

tern.command({
	id = "open",
	title = "Automations: Open",
	icon = "list",
	run = function(cx)
		openManager(cx, {})
	end,
})

tern.command({
	id = "runs",
	title = "Automations: Show runs",
	icon = "list",
	run = function(cx)
		openManager(cx, { "runs" })
	end,
})

tern.command({
	id = "run-now",
	title = "Automations: Run now",
	icon = "play",
	run = function(cx)
		local definitions, errors = files.loadDefinitions()
		if #definitions == 0 then
			cx:toast("error", "No automations to run", errors[1])
			return
		end
		local items = {}
		for _, definition in definitions do
			table.insert(items, {
				label = if definition.name ~= "" then definition.name else definition.id,
				detail = definition.id,
				automation = definition.id,
			})
		end
		cx:pick({ items = items, placeholder = "Automation to run now", action = "run" }):next(function(item, _, nextCx)
			if not item or not nextCx then
				return
			end
			local id = tostring(item.automation)
			tern.fs.mkdir(files.paths.requests)
			tern.fs.write(`{files.paths.requests}/{id}`, "")
			nextCx:toast("success", `Queued {item.label}`, "It starts within 15 seconds, without its precheck.")
		end)
	end,
})
