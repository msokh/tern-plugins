--!strict

export type Paths = {
	home: string,
	configDir: string,
	config: string,
	state: string,
	backups: string,
	requests: string,
	runs: string,
	worktrees: string,
	events: string,
	inbox: string,
	rejected: string,
	status: string,
}

-- `override` is TERN_AUTOMATIONS_HOME: one directory holding `config/` and `state/`, so a smoke
-- run never touches the real settings. Without it, the standard XDG-style locations under `home`.
local function resolve(home: string, override: string?): Paths
	local configDir, state
	if override and override ~= "" then
		configDir, state = `{override}/config`, `{override}/state`
	else
		configDir, state = `{home}/.config/tern-automations`, `{home}/.local/state/tern-automations`
	end
	return {
		home = home,
		configDir = configDir,
		config = `{configDir}/automations.json`,
		state = state,
		backups = `{state}/backups`,
		requests = `{state}/requests`,
		runs = `{state}/runs`,
		worktrees = `{state}/worktrees`,
		events = `{state}/events`,
		inbox = `{state}/events/inbox`,
		rejected = `{state}/events/rejected`,
		status = `{state}/status.md`,
	}
end

return {
	resolve = resolve,
}
