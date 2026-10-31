--!strict
local config = require("./config")

local HOME = tern.getenv("HOME") or ""
local STATE = `{HOME}/.local/state/tern-automations`

local paths = {
	home = HOME,
	config = `{HOME}/.config/tern-automations/automations.json`,
	requests = `{STATE}/requests`,
	status = `{STATE}/status.md`,
}

local MAX_CONFIG_BYTES = 1024 * 1024

local function loadConfig(): ({ config.Automation }, { string })
	if not tern.fs.exists(paths.config) then
		return {}, { `no config at {paths.config}` }
	end
	local ok, doc = pcall(function()
		return tern.json.decode(tern.fs.read(paths.config, MAX_CONFIG_BYTES))
	end)
	if not ok then
		return {}, { `cannot read {paths.config}: {doc}` }
	end
	return config.parse(doc, HOME)
end

return {
	paths = paths,
	loadConfig = loadConfig,
}
