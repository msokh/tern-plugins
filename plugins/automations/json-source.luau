--!strict

export type Range = { first: number, last: number }
export type Member = { key: string, range: Range, value: Range }

local function whitespace(text: string, first: number): number
	return string.find(text, "[^ \t\r\n]", first) or #text + 1
end

local function stringEnd(text: string, first: number): number
	local pos = first + 1
	while pos <= #text do
		local byte = string.byte(text, pos)
		if byte == 34 then
			return pos
		elseif byte == 92 then
			pos += 2
		else
			pos += 1
		end
	end
	error("unterminated string in decoded JSON")
end

-- Only locate tokens after the host decoder has accepted the complete document.
local function valueRange(text: string, first: number): Range
	first = whitespace(text, first)
	local byte = string.byte(text, first)
	if byte == 34 then
		return { first = first, last = stringEnd(text, first) }
	elseif byte == 123 or byte == 91 then
		local depth = 1
		local pos = first + 1
		while depth > 0 and pos <= #text do
			byte = string.byte(text, pos)
			if byte == 34 then
				pos = stringEnd(text, pos)
			elseif byte == 123 or byte == 91 then
				depth += 1
			elseif byte == 125 or byte == 93 then
				depth -= 1
			end
			pos += 1
		end
		return { first = first, last = pos - 1 }
	end
	local pos = first
	while pos <= #text do
		byte = string.byte(text, pos)
		if byte == 44 or byte == 93 or byte == 125 or byte == 32 or byte == 9 or byte == 13 or byte == 10 then
			break
		end
		pos += 1
	end
	return { first = first, last = pos - 1 }
end

local function members(text: string, object: Range, decode: (string) -> unknown): { Member }
	local out: { Member } = {}
	local pos = whitespace(text, object.first + 1)
	while pos < object.last do
		local first = pos
		local last = stringEnd(text, first)
		local key = decode(string.sub(text, first, last))
		assert(type(key) == "string", "decoded JSON object keys are strings")
		pos = whitespace(text, last + 1)
		local value = valueRange(text, pos + 1)
		table.insert(out, { key = key, range = { first = first, last = value.last }, value = value })
		pos = whitespace(text, value.last + 1)
		if pos < object.last then
			pos = whitespace(text, pos + 1)
		end
	end
	return out
end

local function items(text: string, array: Range): { Range }
	local out: { Range } = {}
	local pos = whitespace(text, array.first + 1)
	while pos < array.last do
		local value = valueRange(text, pos)
		table.insert(out, value)
		pos = whitespace(text, value.last + 1)
		if pos < array.last then
			pos = whitespace(text, pos + 1)
		end
	end
	return out
end

local function slice(text: string, range: Range): string
	return string.sub(text, range.first, range.last)
end

return {
	range = valueRange,
	members = members,
	items = items,
	slice = slice,
}
