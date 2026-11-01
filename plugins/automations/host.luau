--!strict
local manager = require("./manager")
local runtime = require("./runtime")

manager.register(runtime)
runtime.start()
