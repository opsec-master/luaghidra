-- Access to the Ghidra host context, plus the small conversions every other
-- @ghidra module needs. Kept separate so modules can depend on it without
-- pulling in the whole core module.

local internal = {}

local resolved = false
local context = nil

--- Returns the LuaGhidraContext for this interpreter, or nil outside Ghidra.
function internal.tryContext()
	if not resolved then
		resolved = true
		local ok, value = pcall(require, "@host")
		context = if ok then value else nil
	end
	return context
end

--- Returns the LuaGhidraContext, raising a clear error when there is none.
function internal.context()
	local value = internal.tryContext()
	if value == nil then
		error("the @ghidra module needs a Ghidra host; it is unavailable in this interpreter", 3)
	end
	return value
end

--- Returns the open Program, raising when no program is open.
function internal.program()
	local program = internal.context():getProgram()
	if program == nil then
		error("no program is open", 3)
	end
	return program
end

--- Imports a Java class once and caches it by name.
internal.classes = setmetatable({}, {
	__index = function(self, name: string)
		local class = java.import(name)
		rawset(self, name, class)
		return class
	end,
	__mode = "v",
})

--- Turns anything Ghidra returns a collection as into a generic-for iterator:
--- a Java Iterator or Iterable, a Java array, a Luau array, or an iterator
--- function. Cancelling the task monitor stops the loop with an error, matching
--- how a Java Ghidra script aborts.
function internal.iterate(source)
	if source == nil then
		return function()
			return nil
		end
	end
	if typeof(source) == "function" then
		return source
	end

	local step
	if typeof(source) == "table" then
		local index = 0
		step = function()
			index += 1
			return source[index]
		end
	elseif internal.hasMethod(source, "hasNext") then
		step = function()
			if source:hasNext() then
				return source:next()
			end
			return nil
		end
	elseif internal.hasMethod(source, "iterator") then
		local iterator = source:iterator()
		step = function()
			if iterator:hasNext() then
				return iterator:next()
			end
			return nil
		end
	else
		-- A Java array: #source and source[i] are supported directly.
		local length = #source
		local index = 0
		step = function()
			index += 1
			if index <= length then
				return source[index]
			end
			return nil
		end
	end

	local context = internal.tryContext()
	if context == nil then
		return step
	end
	local monitor = context:getMonitor()
	return function()
		if monitor:isCancelled() then
			error("script cancelled", 0)
		end
		return step()
	end
end

--- True when a Java value responds to a method of this name.
function internal.hasMethod(value, name: string): boolean
	return type(value) == "userdata" and typeof(value[name]) == "function"
end

--- Collects any collection into a Luau array, stopping at `limit` if given.
---
--- Unlike iterating, this indexes Java and Luau arrays by length, so an array
--- holding nulls keeps its shape instead of ending early at the first one.
function internal.collect(source, limit: number?)
	if source == nil then
		return {}
	end

	if typeof(source) ~= "function" and not internal.hasMethod(source, "hasNext")
		and not internal.hasMethod(source, "iterator") then
		local length = #source
		if limit ~= nil then
			length = math.min(length, limit)
		end
		local out = table.create(length)
		for index = 1, length do
			out[index] = source[index]
		end
		return out
	end

	local step = internal.iterate(source)
	local out = {}
	local count = 0
	for value in step do
		count += 1
		out[count] = value
		if limit ~= nil and count >= limit then
			break
		end
	end
	return out
end

return internal
