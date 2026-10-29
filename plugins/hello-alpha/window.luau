tern.command({
	id = "greet",
	title = "Hello Alpha",
	run = function(cx)
		cx:toast("info", "Hello from Alpha")
	end,
})
