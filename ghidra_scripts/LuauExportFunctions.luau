--@category Luau.Examples
--@description Writes a JSON report of every function to a file.

local ghidra = require("@ghidra")
local io = require("@ghidra/io")
local blocks = require("@ghidra/blocks")
local refs = require("@ghidra/references")
local ui = require("@ghidra/ui")

local program = ghidra.program()
local path = ui.askString("Export functions", "Write the report to:",
	`~/{program.name}-functions.json`)

local task = ghidra.task("Collecting functions", { max = program.functionCount })

local report = { program = ghidra.info(), functions = {} }

for func in ghidra.functions() do
	table.insert(report.functions, {
		name = func.name,
		entry = tostring(func.entry),
		size = func.size,
		signature = func.signature,
		callers = refs.countTo(func.entry),
		callees = #func:callees(),
		blocks = #ghidra.collect(blocks.of(func)),
	})
	task:step()
end

io.writeJson(path, report)
print(`wrote {#report.functions} function(s) to {path}`)
