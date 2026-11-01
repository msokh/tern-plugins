--!strict


export type Encoder = (value: unknown, pretty: boolean?) -> string

local INDENT = "\t"

-- Keys in `first` come first, in that order; the rest follow alphabetically.
local function encode(leaf: Encoder, first: { string }, value: unknown, pretty: boolean, depth: number): string
	if type(value) ~= "table" then
		return leaf(value, false)
	end
	local names: { string } = {}
	local byName: { [string]: unknown } = {}
	local positions: { number } = {}
	local byPosition: { [number]: unknown } = {}
	local count = 0
	for key, item in value do
		count += 1
		if type(key) == "number" then
			table.insert(positions, key)
			byPosition[key] = item
		else
			table.insert(names, tostring(key))
			byName[tostring(key)] = item
		end
	end
	if count == 0 then
		return leaf(value, false)
	end
	local sep, pad, inner = ",", "", ""
	local colon = ":"
	if pretty then
		sep = ",\n" .. string.rep(INDENT, depth + 1)
		pad = "\n" .. string.rep(INDENT, depth)
		inner = "\n" .. string.rep(INDENT, depth + 1)
		colon = ": "
	end
	local parts: { string } = {}
	if #names == 0 then
		table.sort(positions)
		for _, position in positions do
			table.insert(parts, encode(leaf, first, byPosition[position], pretty, depth + 1))
		end
		return "[" .. inner .. table.concat(parts, sep) .. pad .. "]"
	end
	local rank: { [string]: number } = {}
	for i, name in first do
		rank[name] = i
	end
	table.sort(names, function(a, b)
		local ra, rb = rank[a] or math.huge, rank[b] or math.huge
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	for _, name in names do
		table.insert(parts, leaf(name, false) .. colon .. encode(leaf, first, byName[name], pretty, depth + 1))
	end
	return "{" .. inner .. table.concat(parts, sep) .. pad .. "}"
end

return {
	encode = function(leaf: Encoder, first: { string }, value: unknown, pretty: boolean): string
		return encode(leaf, first, value, pretty, 0)
	end,
}
