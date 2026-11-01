--!strict
local engine = require("./engine")
local files = require("./files")
local schedule = require("./schedule")


local function toDate(epoch: number): schedule.Date
	local d = os.date("*t", epoch)
	if type(d) == "string" then
		error("os.date returned text")
	end
	return { min = d.min, hour = d.hour, day = d.day, month = d.month, wday = d.wday }
end

local function format(fmt: string, epoch: number): string
	local text = os.date(fmt, epoch)
	return if type(text) == "string" then text else ""
end

return engine.create({
	host = tern,
	paths = files.paths,
	clock = { time = os.time, date = toDate, format = format, mono = tern.now },
	pluginDir = tern.plugin.dir,
})
