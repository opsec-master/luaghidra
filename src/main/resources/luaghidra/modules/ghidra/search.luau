-- Searching a program's bytes, strings, and instructions.
--
--     local search = require("@ghidra/search")
--
--     for hit in search.bytes("\x55\x8b\xec") do print(hit) end
--     for hit in search.pattern("55 8b ?? ec") do print(hit) end

local internal = require("@ghidra/internal/host")

local search = {}

local function address(value)
	return internal.context():toAddress(value)
end

-- Ghidra's byte search takes a value array and a mask array; a zero mask byte
-- means "match anything here". Byte values are written as 0..255 and converted
-- to Java's signed bytes on the way in.
local function byteArrays(values: { number }, mask: { number })
	local byteClass = java.import("byte")
	local valueArray = java.array(byteClass, #values)
	local maskArray = java.array(byteClass, #values)
	for index = 1, #values do
		valueArray[index] = values[index]
		maskArray[index] = mask[index]
	end
	return valueArray, maskArray
end

local function bytesOf(value)
	local values, mask = {}, {}
	if typeof(value) == "string" then
		for index = 1, #value do
			values[index] = string.byte(value, index)
			mask[index] = 0xff
		end
	elseif typeof(value) == "table" then
		for index = 1, #value do
			local byte = value[index]
			values[index] = if byte ~= nil then byte % 256 else 0
			mask[index] = if byte ~= nil then 0xff else 0
		end
	else
		error("search expects a byte string or an array of byte values", 3)
	end
	if #values == 0 then
		error("the search value is empty", 3)
	end
	return byteArrays(values, mask)
end

--- Parses "55 8b ?? ec" into value and mask arrays, where ?? is a wildcard.
local function parsePattern(pattern: string)
	local values, mask = {}, {}
	local count = 0
	for token in string.gmatch(pattern, "%S+") do
		count += 1
		if token == "??" or token == "?" or token == ".." then
			values[count] = 0
			mask[count] = 0
		else
			local byte = tonumber(token, 16)
			if byte == nil then
				error(`'{token}' is not a hex byte or a ?? wildcard`, 3)
			end
			values[count] = byte % 256
			mask[count] = 0xff
		end
	end
	if count == 0 then
		error("the pattern is empty", 3)
	end
	return byteArrays(values, mask)
end

local function findAll(values, mask, options)
	options = options or {}
	local memory = internal.program():getMemory()
	local monitor = internal.context():getMonitor()
	local from = if options.from ~= nil then address(options.from) else internal.program():getMinAddress()
	local limit = options.limit
	local found = 0

	return function()
		if from == nil or (limit ~= nil and found >= limit) then
			return nil
		end
		local hit = memory:findBytes(from, values, mask, true, monitor)
		if hit == nil then
			from = nil
			return nil
		end
		found += 1
		from = hit:next()
		return hit
	end
end

--- Iterates addresses whose bytes match exactly. `value` is a byte string or an
--- array of byte values in which nil means "any byte".
function search.bytes(value, options: { from: any?, limit: number? }?)
	local values, mask = bytesOf(value)
	return findAll(values, mask, options)
end

--- Iterates addresses matching a hex pattern such as "55 8b ?? ec", where ??
--- matches any byte.
function search.pattern(pattern: string, options: { from: any?, limit: number? }?)
	local values, mask = parsePattern(pattern)
	return findAll(values, mask, options)
end

--- The first address matching a hex pattern, or nil.
function search.firstPattern(pattern: string, options: { from: any? }?)
	for hit in search.pattern(pattern, options) do
		return hit
	end
	return nil
end

--- Iterates defined strings whose text matches a Luau pattern.
function search.strings(pattern: string)
	local step = internal.iterate(internal.context():definedStrings())
	return function()
		for data in step do
			local text = internal.context():stringValue(data)
			if text ~= nil and string.find(text, pattern) then
				return data
			end
		end
		return nil
	end
end

--- Iterates functions whose name matches a Luau pattern.
function search.functions(pattern: string)
	local step = require("@ghidra").functions()
	return function()
		for func in step do
			if string.find(func:getName(), pattern) then
				return func
			end
		end
		return nil
	end
end

--- Iterates symbols whose name matches a Luau pattern.
function search.symbols(pattern: string, options: { dynamic: boolean? }?)
	local step = require("@ghidra/symbols").all(options)
	return function()
		for symbol in step do
			if string.find(symbol:getName(), pattern) then
				return symbol
			end
		end
		return nil
	end
end

--- Iterates instructions whose text matches a Luau pattern.
function search.instructions(pattern: string, options)
	local step = require("@ghidra").instructions(options)
	return function()
		for instruction in step do
			if string.find(tostring(instruction), pattern) then
				return instruction
			end
		end
		return nil
	end
end

return search
