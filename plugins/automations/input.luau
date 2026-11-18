--!strict

type Checkpoint = { text: string, cursor: number, anchor: number? }

export type Field = {
	text: string,
	cursor: number,
	anchor: number?,
	multiline: boolean,
	past: { Checkpoint },
	future: { Checkpoint },
	typing: boolean,
}

export type Props = { text: string, cursor: number, anchor: number? }

local Input = {}
local HISTORY_LIMIT = 100

local function byteAt(text: string, position: number): number
	return utf8.offset(text, position + 1) or (#text + 1)
end

local function lineEndings(text: string): string
	return (string.gsub(string.gsub(text, "\r\n", "\n"), "\r", "\n"))
end

local function isControl(code: number, multiline: boolean): boolean
	if multiline and (code == 10 or code == 9) then
		return false
	end
	return code < 32 or (code >= 127 and code <= 159) or code == 0x2028 or code == 0x2029
end

function Input.valid(text: string, multiline: boolean): boolean
	if utf8.len(text) == nil then
		return false
	end
	for _, code in utf8.codes(text) do
		if isControl(code, multiline) then
			return false
		end
	end
	return true
end

function Input.new(text: string?, multiline: boolean?): Field
	local multi = multiline == true
	local value = if multi then lineEndings(text or "") else text or ""
	if not Input.valid(value, multi) then
		value = ""
	end
	return { text = value, cursor = utf8.len(value) or 0, anchor = nil, multiline = multi, past = {}, future = {}, typing = false }
end

function Input.length(field: Field): number
	return utf8.len(field.text) or 0
end

function Input.setText(field: Field, text: string)
	local value = if field.multiline then lineEndings(text) else text
	field.text = if Input.valid(value, field.multiline) then value else ""
	field.cursor = Input.length(field)
	field.anchor = nil
	table.clear(field.past)
	table.clear(field.future)
	field.typing = false
end

function Input.focus(field: Field)
	field.typing = false
end

local function utf16(text: string, position: number): number
	local units, count = 0, 0
	for _, code in utf8.codes(text) do
		if count >= position then
			break
		end
		units += if code > 0xFFFF then 2 else 1
		count += 1
	end
	return units
end

function Input.props(field: Field): Props
	return {
		text = field.text,
		cursor = utf16(field.text, field.cursor),
		anchor = if field.anchor ~= nil then utf16(field.text, field.anchor) else nil,
	}
end

local function bounds(field: Field): (number, number)
	local anchor = field.anchor or field.cursor
	return math.min(anchor, field.cursor), math.max(anchor, field.cursor)
end

function Input.selection(field: Field): string
	local first, last = bounds(field)
	return string.sub(field.text, byteAt(field.text, first), byteAt(field.text, last) - 1)
end

local function replace(field: Field, first: number, last: number, text: string, typing: boolean?)
	local updated = string.sub(field.text, 1, byteAt(field.text, first) - 1)
		.. text
		.. string.sub(field.text, byteAt(field.text, last))
	if updated ~= field.text then
		if not (typing and field.typing) then
			table.insert(field.past, { text = field.text, cursor = field.cursor, anchor = field.anchor })
			if #field.past > HISTORY_LIMIT then
				table.remove(field.past, 1)
			end
		end
		table.clear(field.future)
		field.typing = typing == true
	else
		field.typing = false
	end
	field.text = updated
	field.cursor = first + (utf8.len(text) or 0)
	field.anchor = nil
end

local function move(field: Field, position: number, extend: boolean)
	if extend then
		field.anchor = field.anchor or field.cursor
	else
		field.anchor = nil
	end
	field.cursor = position
end

local function codes(text: string): { number }
	local out = {}
	for _, code in utf8.codes(text) do
		table.insert(out, code)
	end
	return out
end

local function lineAround(points: { number }, position: number): (number, number)
	local first = position
	while first > 0 and points[first] ~= 10 do
		first -= 1
	end
	local last = position
	while last < #points and points[last + 1] ~= 10 do
		last += 1
	end
	return first, last
end

local function moveLine(field: Field, down: boolean, extend: boolean)
	local points = codes(field.text)
	local first, last = lineAround(points, field.cursor)
	local column = field.cursor - first
	local target
	if down then
		if last >= #points then
			target = #points
		else
			local nextFirst = last + 1
			local _, nextLast = lineAround(points, nextFirst)
			target = math.min(nextFirst + column, nextLast)
		end
	else
		if first == 0 then
			target = 0
		else
			local previousLast = first - 1
			local previousFirst = lineAround(points, previousLast)
			target = math.min(previousFirst + column, previousLast)
		end
	end
	move(field, target, extend)
end

local function normalize(text: string, multiline: boolean): string
	local value = lineEndings(text)
	if multiline then
		return value
	end
	value = string.gsub(value, "\n+$", "")
	return (string.gsub(value, "\n", " "))
end

local function moveHistory(field: Field, source: { Checkpoint }, target: { Checkpoint }): boolean
	local previous = table.remove(source)
	if previous == nil then
		return false
	end
	table.insert(target, { text = field.text, cursor = field.cursor, anchor = field.anchor })
	field.text, field.cursor, field.anchor = previous.text, previous.cursor, previous.anchor
	return true
end

function Input.key(field: Field, key: Key): (boolean, string?)
	local name = key.name
	local typing = key.text ~= nil and key.text ~= "" and name ~= "paste"
		and name ~= "enter" and name ~= "tab" and name ~= "escape" and name ~= "esc"
		and not (key.meta or key.ctrl)
	if not typing then
		field.typing = false
	end
	if (key.meta or key.ctrl) and string.lower(name) == "z" then
		if key.shift then
			return moveHistory(field, field.future, field.past), nil
		end
		return moveHistory(field, field.past, field.future), nil
	end
	local length = Input.length(field)
	if key.meta and string.lower(name) == "a" then
		field.anchor, field.cursor = 0, length
	elseif name == "home" or (key.meta and name == "left") then
		move(field, 0, key.shift)
	elseif name == "end" or (key.meta and name == "right") then
		move(field, length, key.shift)
	elseif name == "left" or name == "right" then
		local first, last = bounds(field)
		local position
		if not key.shift and first ~= last then
			position = if name == "left" then first else last
		else
			position = math.clamp(field.cursor + (if name == "left" then -1 else 1), 0, length)
		end
		move(field, position, key.shift)
	elseif (name == "up" or name == "down") and field.multiline then
		moveLine(field, name == "down", key.shift)
	elseif name == "backspace" or name == "delete" then
		local first, last = bounds(field)
		if first == last and name == "backspace" then
			first = math.max(0, first - 1)
		elseif first == last then
			last = math.min(length, last + 1)
		end
		replace(field, first, last, "")
	elseif name == "enter" and field.multiline and not (key.ctrl or key.meta) then
		local first, last = bounds(field)
		replace(field, first, last, "\n")
	elseif key.text ~= nil and key.text ~= "" and (name == "paste" or not (key.ctrl or key.meta)) then
		if name == "tab" or name == "escape" or name == "esc" or name == "enter" then
			return false, nil
		end
		local typed = normalize(key.text, field.multiline)
		if not Input.valid(typed, field.multiline) then
			return true, "Use text without control characters."
		end
		local first, last = bounds(field)
		replace(field, first, last, typed, typing)
	else
		return false, nil
	end
	return true, nil
end

return Input
