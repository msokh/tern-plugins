local schedule = require("../schedule")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL " .. name)
	end
end

local function utc(epoch: number): schedule.Date
	local d = os.date("!*t", epoch)
	assert(type(d) ~= "string")
	return { min = d.min, hour = d.hour, day = d.day, month = d.month, wday = d.wday }
end

local function cron(text: string): schedule.Cron
	local c, err = schedule.parse(text)
	assert(c, err)
	return c
end

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

check("next is strictly after", schedule.next(cron("35 9 * * *"), SAT_0935, 3 * 86400, utc) == SAT_0935 + 86400)
check("next finds a later minute today", schedule.next(cron("50 9 * * *"), SAT_0935, 86400, utc) == SAT_0935 + 900)
check("next skips to a later day", schedule.next(cron("0 0 * * 1"), SAT_0935, 7 * 86400, utc) == SAT_0935 + 86400 + 14 * 3600 + 25 * 60)
check("next gives up past the horizon", schedule.next(cron("0 0 29 2 *"), SAT_0935, 30 * 86400, utc) == nil)

check("four fields rejected", schedule.parse("* * * *") == nil)
check("out of range rejected", schedule.parse("60 * * * *") == nil)
check("inverted range rejected", schedule.parse("* 5-3 * * *") == nil)
check("names rejected", schedule.parse("0 9 * * MON") == nil)

if failures > 0 then
	error(failures .. " failed")
end

require("./config")
require("./events")
require("./runtime")
print("ok")
