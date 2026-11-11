--!strict
tern.command({
	id = "open",
	title = "UI Gallery: Open",
	icon = "list",
	run = function(cx)
		cx:new_block("ui-gallery.gallery", {}, "tab")
	end,
})
