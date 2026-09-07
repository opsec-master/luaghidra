--@category Luau.Examples
--@description Prints every call in the program with the arguments the decompiler worked out.

local ghidra = require("@ghidra")
local pcode = require("@ghidra/pcode")

-- Reads an argument the way a reader would: a string if it points at one, a
-- number if the decompiler knows it, and the varnode itself otherwise.
local function describe(argument): string
	local text = pcode.stringOf(argument)
	if text ~= nil then
		return string.format("%q", text)
	end
	local value = pcode.constant(argument)
	if value ~= nil then
		return `0x{string.format("%x", value)}`
	end
	local high = argument.high
	if high ~= nil and high.name ~= nil and high.name ~= "UNNAMED" then
		return high.name
	end
	return tostring(argument)
end

local calls = 0
for func in ghidra.functions() do
	if func:isThunk() or func.external then
		continue
	end
	for call in func:calls() do
		local arguments = {}
		for index, argument in call.args do
			arguments[index] = describe(argument)
		end
		local name = if call.targetFunction ~= nil
			then call.targetFunction.name
			else (if call.indirect then "(indirect)" else tostring(call.target))
		print(`{call.at}  {func.name} -> {name}({table.concat(arguments, ", ")})`)
		calls += 1
	end
end

print(`{calls} call site(s)`)
