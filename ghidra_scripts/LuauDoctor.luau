--@category Luau
--@description Reports what the LuaGhidra runtime can see, for diagnosing setup problems.

local ghidra = require("@ghidra")

local function report(label: string, value: any)
	print(string.format("%-22s %s", label .. ":", tostring(value)))
end

local function check(label: string, body: () -> any)
	local ok, result = pcall(body)
	report(label, if ok then result else `unavailable (${result})`)
end

print("LuaGhidra")
print(string.rep("-", 60))

report("luau version", _VERSION)
check("bridge", function()
	return java.import("luaghidra.LuauNativeBridge"):version()
end)
check("platform", function()
	return java.import("luaghidra.LuauNativeBridge"):ghidraPlatformName()
end)
check("ghidra version", function()
	return java.import("ghidra.framework.Application"):getApplicationVersion()
end)

print()
report("headless", ghidra.isHeadless())
report("tool", ghidra.tool())

local program = ghidra.currentProgram()
if program == nil then
	print("program:               none open")
else
	report("program", program.name)
	report("language", program.languageId)
	report("image base", program.imageBase)
	report("address spaces", table.concat((function()
		local names = {}
		for _, space in require("@ghidra/addresses").spaces() do
			table.insert(names, space.name)
		end
		return names
	end)(), ", "))
	report("type managers", table.concat((function()
		local names = {}
		for _, manager in require("@ghidra/datatypes").managers() do
			table.insert(names, `{manager.name} ({manager.kind})`)
		end
		return names
	end)(), ", "))
	report("functions", program.functionCount)
	report("cursor", ghidra.currentAddress())
	report("selection", ghidra.selection())

	check("decompiler", function()
		local func = ghidra.collect(ghidra.functions(), 1)[1]
		if func == nil then
			return "no functions to test with"
		end
		local result = func:decompile({ timeout = 20 })
		return if result.ok then `ok (decompiled {func.name})` else `failed: {result.error}`
	end)
end

print()
for _, name in { "@ghidra", "@ghidra/addresses", "@ghidra/analysis", "@ghidra/blocks",
	"@ghidra/bookmarks", "@ghidra/datatypes", "@ghidra/decompiler", "@ghidra/io",
	"@ghidra/memory", "@ghidra/pcode", "@ghidra/references", "@ghidra/search",
	"@ghidra/symbols", "@ghidra/types", "@ghidra/ui" } do
	local ok = pcall(require, name)
	report(name, if ok then "loaded" else "MISSING")
end
