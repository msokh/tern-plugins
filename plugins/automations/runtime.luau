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

-- A plugin host's PATH is only the system directories, so `tern` itself is found by absolute path.
local function ternExecutable(): string?
	local home = tern.getenv("HOME") or ""
	local candidates = {
		tern.getenv("TERN_EXE"),
		`{home}/.local/bin/tern`,
		"/Applications/Tern.app/Contents/MacOS/tern",
		"/opt/homebrew/bin/tern",
		"/usr/local/bin/tern",
	}
	for _, path in candidates do
		if path and path ~= "" and tern.fs.exists(path) then
			return path
		end
	end
	return nil
end

return engine.create({
	host = tern,
	paths = files.paths,
	clock = { time = os.time, date = toDate, format = format, mono = tern.now },
	pluginDir = tern.plugin.dir,
	ternExe = ternExecutable(),
})
