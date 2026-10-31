--!strict
local files = require("./files")

tern.command({
	id = "run-now",
	title = "Automations: Run now",
	icon = "play",
	run = function(cx)
		local automations, errors = files.loadConfig()
		if #automations == 0 then
			cx:toast("error", "No automations to run", errors[1])
			return
		end
		local items = {}
		for _, a in automations do
			local last = (tern.kv.get(`runs:{a.id}`) or {})[1]
			local detail = a.cronText .. (if last then ` · last {last.phase}` else "")
			table.insert(items, { label = a.id, detail = detail })
		end
		cx:pick({ items = items, placeholder = "Automation to run now", action = "run" }):next(function(item, _, nextCx)
			if not item or not nextCx then
				return
			end
			tern.fs.mkdir(files.paths.requests)
			tern.fs.write(`{files.paths.requests}/{item.label}`, "")
			nextCx:toast("success", `Queued {item.label}`, "It starts within 15 seconds, without its precheck.")
		end)
	end,
})

tern.command({
	id = "status",
	title = "Automations: Show status",
	icon = "list",
	run = function(cx)
		if not tern.fs.exists(files.paths.status) then
			cx:toast("info", "No status yet", files.paths.status)
			return
		end
		cx:open(files.paths.status, "beside")
	end,
})
