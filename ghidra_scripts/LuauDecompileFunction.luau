--@category Luau.Examples
--@description Decompiles the function under the cursor and prints its C.

local ghidra = require("@ghidra")

local address = ghidra.currentAddress()
if address == nil then
	error("place the cursor inside a function first")
end

local func = ghidra.functionContaining(address)
if func == nil then
	error(`no function contains {address}`)
end

local result = func:decompile()
if not result.ok then
	error(`could not decompile {func.name}: {result.error}`)
end

print(result.c)
