--!strict

-- Five-field cron: minute hour day-of-month month day-of-week (0 or 7 is Sunday).
-- Each field takes `*`, `N`, `A-B`, a `/STEP` on either, and comma lists of those.

export type Cron = {
	minute: { [number]: boolean },
	hour: { [number]: boolean },
	dom: { [number]: boolean },
	month: { [number]: boolean },
	dow: { [number]: boolean },
	anyDom: boolean,
	anyDow: boolean,
}

export type Date = { min: number, hour: number, day: number, month: number, wday: number }

local RANGES = {
	{ name = "minute", lo = 0, hi = 59 },
	{ name = "hour", lo = 0, hi = 23 },
	{ name = "dom", lo = 1, hi = 31 },
	{ name = "month", lo = 1, hi = 12 },
	{ name = "dow", lo = 0, hi = 7 },
}

local function parseField(text: string, lo: number, hi: number): ({ [number]: boolean }?, string?)
	local set = {}
	for part in string.gmatch(text, "[^,]+") do
		local range, step = string.match(part, "^([^/]+)/(%d+)$")
		range = range or part
		local stride = if step then tonumber(step) :: number else 1
		local first, last
		if range == "*" then
			first, last = lo, hi
		else
			local a, b = string.match(range, "^(%d+)-(%d+)$")
			if a then
				first, last = tonumber(a) :: number, tonumber(b) :: number
			elseif string.match(range, "^%d+$") then
				first = tonumber(range) :: number
				last = if step then hi else first
			else
				return nil, `bad term "{part}"`
			end
		end
		if stride < 1 or first < lo or last > hi or first > last then
			return nil, `"{part}" is outside {lo}-{hi}`
		end
		for v = first, last, stride do
			set[v] = true
		end
	end
	if next(set) == nil then
		return nil, "empty field"
	end
	return set, nil
end

local function parse(text: string): (Cron?, string?)
	local fields = {}
	for field in string.gmatch(text, "%S+") do
		table.insert(fields, field)
	end
	if #fields ~= 5 then
		return nil, `cron "{text}" needs 5 fields, has {#fields}`
	end
	local sets = {}
	for i, range in RANGES do
		local set, err = parseField(fields[i], range.lo, range.hi)
		if not set then
			return nil, `cron "{text}" {range.name}: {err}`
		end
		sets[range.name] = set
	end
	if sets.dow[7] then
		sets.dow[0] = true
	end
	return {
		minute = sets.minute,
		hour = sets.hour,
		dom = sets.dom,
		month = sets.month,
		dow = sets.dow,
		anyDom = string.sub(fields[3], 1, 1) == "*",
		anyDow = string.sub(fields[5], 1, 1) == "*",
	}, nil
end

local function dayMatches(cron: Cron, d: Date): boolean
	local domHit = cron.dom[d.day] == true
	local dowHit = cron.dow[d.wday - 1] == true
	-- Why: standard cron ORs the two day fields only when neither starts with `*` (so `*/2` still ANDs).
	if cron.anyDom or cron.anyDow then
		return domHit and dowHit
	end
	return domHit or dowHit
end

local function matches(cron: Cron, d: Date): boolean
	return cron.minute[d.min] == true and cron.hour[d.hour] == true and cron.month[d.month] == true and dayMatches(cron, d)
end

-- The latest minute in (after, upto] that matches, as epoch seconds; both bounds are minute-aligned.
local function latest(cron: Cron, after: number, upto: number, toDate: (number) -> Date): number?
	local t = upto
	while t > after do
		if matches(cron, toDate(t)) then
			return t
		end
		t -= 60
	end
	return nil
end

-- The first minute after `after` (and within `horizon` seconds of it) that matches, as epoch seconds.
local function nextSlot(cron: Cron, after: number, horizon: number, toDate: (number) -> Date): number?
	local t = after - after % 60 + 60
	local stop = after + horizon
	while t <= stop do
		local d = toDate(t)
		if not (cron.month[d.month] and dayMatches(cron, d) and cron.hour[d.hour]) then
			t += (60 - d.min) * 60
		elseif not cron.minute[d.min] then
			t += 60
		else
			return t
		end
	end
	return nil
end

return {
	parse = parse,
	matches = matches,
	latest = latest,
	next = nextSlot,
}
