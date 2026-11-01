--!strict


export type Object = { [string]: unknown }

local function object(value: unknown): Object?
	if type(value) ~= "table" then
		return nil
	end
	local out: Object = {}
	for key, item in value do
		if type(key) ~= "string" then
			return nil
		end
		out[key] = item
	end
	return out
end

local function array(value: unknown): { unknown }?
	if type(value) ~= "table" then
		return nil
	end
	local out: { unknown } = {}
	local count = 0
	for key, item in value do
		if type(key) ~= "number" then
			return nil
		end
		count += 1
		out[key] = item
	end
	for i = 1, count do
		if out[i] == nil then
			return nil
		end
	end
	return out
end

local function strings(value: unknown): { string }?
	local items = array(value)
	if not items then
		return nil
	end
	local out: { string } = {}
	for _, item in items do
		if type(item) ~= "string" then
			return nil
		end
		table.insert(out, item)
	end
	return out
end

return {
	object = object,
	array = array,
	strings = strings,
}
