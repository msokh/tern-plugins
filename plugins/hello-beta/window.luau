--!strict

tern.command({
	id = "greet",
	title = "Hello Beta",
	run = function(cx)
		cx:toast("info", "Hello from Beta")
	end,
})
