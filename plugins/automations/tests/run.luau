local schedule = require("../schedule")
local config = require("../config")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL " .. name)
	end
end

local function utc(epoch: number): schedule.Date
	return os.date("!*t", epoch) :: any
end

local function cron(text: string): schedule.Cron
	local c, err = schedule.parse(text)
	assert(c, err)
	return c
end

-- 2026-10-31 09:35 UTC, a Saturday.
local SAT_0935 = 1793439300

check("daily slot matches at its minute", schedule.matches(cron("35 9 * * *"), utc(SAT_0935)))
check("daily slot misses the next minute", not schedule.matches(cron("35 9 * * *"), utc(SAT_0935 + 60)))
check("step field matches multiples", schedule.matches(cron("*/5 * * * *"), utc(SAT_0935)))
check("step field skips others", not schedule.matches(cron("*/5 * * * *"), utc(SAT_0935 + 60)))
check("hour step from zero", schedule.matches(cron("35 */3 * * *"), utc(SAT_0935)))
check("weekday range excludes Saturday", not schedule.matches(cron("35 9 * * 1-5"), utc(SAT_0935)))
check("7 means Sunday", schedule.matches(cron("35 9 * * 7"), utc(SAT_0935 + 86400)))
check("restricted day fields OR together", schedule.matches(cron("35 9 1 * 6"), utc(SAT_0935)))
check("day-of-month alone must match", not schedule.matches(cron("35 9 1 * *"), utc(SAT_0935)))
check("lists", schedule.matches(cron("0,35 8,9 * * *"), utc(SAT_0935)))

check("latest picks the newest slot in the window",
	schedule.latest(cron("*/10 * * * *"), SAT_0935 - 3600, SAT_0935, utc) == SAT_0935 - 300)
check("latest includes the upper bound", schedule.latest(cron("35 9 * * *"), SAT_0935 - 60, SAT_0935, utc) == SAT_0935)
check("latest excludes the lower bound", schedule.latest(cron("35 9 * * *"), SAT_0935, SAT_0935 + 600, utc) == nil)

check("four fields rejected", schedule.parse("* * * *") == nil)
check("out of range rejected", schedule.parse("60 * * * *") == nil)
check("inverted range rejected", schedule.parse("* 5-3 * * *") == nil)
check("names rejected", schedule.parse("0 9 * * MON") == nil)

local good = {
	id = "daily-review",
	cron = "35 9 * * *",
	cwd = "~/automations/daily-review",
	command = { "omp", "-p", "@prompt.md" },
}
local automations, errors = config.parse({
	automations = {
		good,
		{ id = "Bad Id", cron = "* * * * *", cwd = "/tmp", command = { "true" } },
		{ id = "daily-review", cron = "0 * * * *", cwd = "/tmp", command = { "true" } },
		{
			id = "gated",
			cron = "0 * * * *",
			cwd = "/tmp",
			command = { "true" },
			precheck = { command = { "~/bin/check" } },
			enabled = false,
		},
		{ id = "relative", cron = "0 * * * *", cwd = "work", command = { "true" } },
	},
}, "/x/example-home")

check("valid entries load past bad ones", #automations == 2)
check("bad id, duplicate id and relative cwd reported", #errors == 3)
check("~ expands in cwd", automations[1].cwd == "/x/example-home/automations/daily-review")
check("command args other than ~ stay as written", automations[1].command[3] == "@prompt.md")
check("grace defaults to 60 minutes", automations[1].graceMinutes == 60)
check("enabled by default", automations[1].enabled)
check("enabled false kept", not automations[2].enabled)
check("~ expands in precheck", automations[2].precheck and automations[2].precheck.command[1] == "/x/example-home/bin/check")
check("precheck timeout defaults to 60 s", automations[2].precheck and automations[2].precheck.timeoutMs == 60000)
check("missing automations array reported", #select(2, config.parse({}, "/h")) == 1)

if failures > 0 then
	error(failures .. " failed")
end
print("ok")
