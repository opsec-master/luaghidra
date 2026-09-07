--@category Luau.Examples
--@description Prints defined strings matching a pattern the user supplies.

local ghidra = require("@ghidra")
local ui = require("@ghidra/ui")

local pattern = ui.askString("Find strings", "Lua pattern to match:", ".")

local matches = 0
for data in ghidra.strings() do
	local text = data.text
	if text ~= nil and string.find(text, pattern) then
		matches += 1
		print(`{data.address}  {string.format("%q", text)}`)
	end
end

print(`{matches} match(es)`)
