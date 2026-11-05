--!strict
local engine = require("../engine")
local paths = require("../paths")
local schedule = require("../schedule")

local JSON_NULL = newproxy()
local JSON_ARRAY = {}

local function encodeLeaf(value: unknown, _pretty: boolean?): string
	if value == JSON_NULL then
		return "null"
	elseif type(value) == "table" then
		return if getmetatable(value) == JSON_ARRAY then "[]" else "{}"
	end
	if type(value) == "string" then
		local escaped = string.gsub(value, '[%c"\\]', function(c: string): string
			if c == '"' then
				return '\\"'
			elseif c == "\\" then
				return "\\\\"
			elseif c == "\n" then
				return "\\n"
			end
			return string.format("\\u%04x", string.byte(c))
		end)
		return '"' .. escaped .. '"'
	elseif type(value) == "number" or type(value) == "boolean" then
		return tostring(value)
	end
	return "{}"
end

local function decode(text: string): unknown
	local pos = 1
	local function ws()
		pos = string.find(text, "[^ \t\r\n]", pos) or #text + 1
	end
	local value: () -> unknown
	local function str(): string
		local out = {}
		pos += 1
		while true do
			local c = string.sub(text, pos, pos)
			if c == "" then
				error("unterminated string")
			elseif c == '"' then
				pos += 1
				return table.concat(out)
			elseif c == "\\" then
				local e = string.sub(text, pos + 1, pos + 1)
				if e == "u" then
					table.insert(out, utf8.char(tonumber(string.sub(text, pos + 2, pos + 5), 16) or 63))
					pos += 6
				else
					table.insert(out, (if e == "n" then "\n" elseif e == "t" then "\t" elseif e == "r" then "\r" else e))
					pos += 2
				end
			else
				table.insert(out, c)
				pos += 1
			end
		end
	end
	function value(): unknown
		ws()
		local c = string.sub(text, pos, pos)
		if c == "{" then
			local out: { [string]: unknown } = {}
			pos += 1
			ws()
			if string.sub(text, pos, pos) == "}" then
				pos += 1
				return out
			end
			while true do
				ws()
				local key = str()
				ws()
				pos += 1
				local member = value()
				if member ~= JSON_NULL then
					out[key] = member
				end
				ws()
				local d = string.sub(text, pos, pos)
				pos += 1
				if d == "}" then
					return out
				elseif d ~= "," then
					error("bad object")
				end
			end
		elseif c == "[" then
			local out: { unknown } = setmetatable({}, JSON_ARRAY)
			pos += 1
			ws()
			if string.sub(text, pos, pos) == "]" then
				pos += 1
				return out
			end
			while true do
				table.insert(out, value())
				ws()
				local d = string.sub(text, pos, pos)
				pos += 1
				if d == "]" then
					return out
				elseif d ~= "," then
					error("bad array")
				end
			end
		elseif c == '"' then
			return str()
		end
		local word = string.match(text, "^[%w%.%-+]+", pos)
		if not word then
			error("bad json")
		end
		pos += #word
		if word == "true" then
			return true
		elseif word == "false" then
			return false
		elseif word == "null" then
			return JSON_NULL
		end
		return tonumber(word)
	end
	local result = value()
	ws()
	if pos <= #text then
		error("trailing text")
	end
	return result
end

local function encodeValue(value: unknown): string
	if type(value) ~= "table" then
		return encodeLeaf(value, false)
	end
	local parts = {}
	local isArray = getmetatable(value) == JSON_ARRAY or #value > 0
	for k, v in value do
		if isArray then
			table.insert(parts, encodeValue(v))
		else
			table.insert(parts, encodeLeaf(tostring(k), false) .. ":" .. encodeValue(v))
		end
	end
	if isArray then
		return "[" .. table.concat(parts, ",") .. "]"
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
export type Call = { argv: { string }, opts: engine.ProcessOpts, reply: (engine.ProcessOut) -> () }

export type Fake = {
	engine: engine.Runtime,
	files: { [string]: string },
	kv: { [string]: unknown },
	calls: { Call },
	paneExit: (pane: number, status: number) -> (),
	panes: { number },
	setNow: (epoch: number) -> (),
	paths: paths.Paths,
}

local function ok(stdout: string?): engine.ProcessOut
	return { status = 0, stdout = stdout or "", stderr = "", timed_out = false }
end

local function failed(status: number): engine.ProcessOut
	return { status = status, stdout = "", stderr = "secret-looking text", timed_out = false }
end

-- `files` and `kv` can be shared between two fakes to model a restart.
local function newFake(root: string, files: { [string]: string }?, kv: { [string]: unknown }?, startAt: number?, ternExe: (string | false)?): Fake
	local fileMap: { [string]: string } = files or {}
	local kvMap: { [string]: unknown } = kv or {}
	local dirs: { [string]: boolean } = {}
	local now = startAt or 1793439300
	local calls: { Call } = {}
	local handlers: { [string]: (engine.PaneExit) -> () } = {}
	local fake: Fake
	local p = paths.resolve("/example-home", root)

	local host: engine.Host = {
		json = { encode = encodeLeaf, decode = decode },
		fs = {
			read = function(path, _max)
				local text = fileMap[path]
				if text == nil then
					error("missing " .. path)
				end
				return text
			end,
			write = function(path, text)
				fileMap[path] = text
			end,
			list = function(dir)
				local names: { string } = {}
				local prefix = dir .. "/"
				local seen: { [string]: boolean } = {}
				local function add(path: string)
					if string.sub(path, 1, #prefix) == prefix then
						local name = string.match(string.sub(path, #prefix + 1), "^[^/]+")
						if name and not seen[name] then
							seen[name] = true
							table.insert(names, name)
						end
					end
				end
				for path in fileMap do
					add(path)
				end
				for path in dirs do
					add(path)
				end
				table.sort(names)
				return names
			end,
			exists = function(path)
				if fileMap[path] ~= nil or dirs[path] then
					return true
				end
				for other in fileMap do
					if string.sub(other, 1, #path + 1) == path .. "/" then
						return true
					end
				end
				return false
			end,
			mkdir = function(path)
				dirs[path] = true
			end,
			remove = function(path)
				fileMap[path] = nil
				dirs[path] = nil
				for other in fileMap do
					if string.sub(other, 1, #path + 1) == path .. "/" then
						fileMap[other] = nil
					end
				end
			end,
		},
		kv = {
			get = function(key)
				local value = kvMap[key]
				return if value == nil then nil else decode(encodeValue(value))
			end,
			set = function(key, value)
				kvMap[key] = value
			end,
		},
		process = {
			run = function(argv, opts, cb)
				table.insert(calls, { argv = argv, opts = opts, reply = cb })
			end,
		},
		timer = function(_ms, _fn)
			return {}
		end,
		on = function(name, fn)
			handlers[name] = fn
		end,
		pane = {
			list = function()
				local out = {}
				for _, pane in fake.panes do
					table.insert(out, { pane = pane })
				end
				return out
			end,
		},
		log = { warn = function() end, error = function() end },
	}
	local function toDate(epoch: number): schedule.Date
		local d = os.date("!*t", epoch)
		assert(type(d) ~= "string")
		return { min = d.min, hour = d.hour, day = d.day, month = d.month, wday = d.wday }
	end
	local instance = engine.create({
		host = host,
		paths = p,
		clock = {
			time = function()
				return now
			end,
			date = toDate,
			format = function(fmt, epoch)
				local text = os.date("!" .. fmt, epoch)
				return if type(text) == "string" then text else ""
			end,
			mono = function()
				return now * 1000
			end,
		},
		pluginDir = "/example-plugin",
		ternExe = if ternExe == false then nil else (ternExe or "/example/tern"),
	})
	local function paneExit(pane: number, status: number)
		local handler = handlers.pane_exited
		assert(handler, "start() registers the pane_exited handler")
		handler({ pane = pane, status = status })
	end
	local function setNow(epoch: number)
		now = epoch
	end
	fake = { engine = instance, files = fileMap, kv = kvMap, calls = calls, panes = {}, paths = p, paneExit = paneExit, setNow = setNow }
	return fake
end


return {
	newFake = newFake,
	ok = ok,
	failed = failed,
	decode = decode,
	encodeLeaf = encodeLeaf,
}
