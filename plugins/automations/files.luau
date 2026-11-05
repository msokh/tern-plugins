--!strict
local config = require("./config")
local paths = require("./paths")

local HOME = tern.getenv("HOME") or ""

local resolved = paths.resolve(HOME, tern.getenv("TERN_AUTOMATIONS_HOME"))

local MAX_CONFIG_BYTES = 1024 * 1024

local function loadDefinitions(): ({ config.Definition }, { string })
	if not tern.fs.exists(resolved.config) then
		return {}, { `no config at {resolved.config}` }
	end
	local ok, text = pcall(tern.fs.read, resolved.config, MAX_CONFIG_BYTES)
	if not ok then
		return {}, { "cannot read the config file" }
	end
	local doc = config.parseDocument(text, tern.json.decode)
	return config.definitions(doc), doc.errors
end

return {
	paths = resolved,
	loadDefinitions = loadDefinitions,
}
