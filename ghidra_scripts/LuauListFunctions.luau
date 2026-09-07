--@category Luau.Examples
--@description Prints every function with its entry point and size.

local ghidra = require("@ghidra")

local program = ghidra.program()
print(`{program.name} — {program.functionCount} functions`)

local task = ghidra.task("Listing functions", { max = program.functionCount })
for func in ghidra.functions() do
	print(string.format("%s  %6d  %s", tostring(func.entry), func.size, func.name))
	task:step()
end
