--@category Luau.Examples
--@description Renames FUN_* functions after the string they reference, if any.

local ghidra = require("@ghidra")

-- Every database change goes inside a transaction, which the helper commits on
-- success and rolls back if anything raises.
local renamed = ghidra.transaction("Rename default functions", function()
	local count = 0
	for func in ghidra.functions() do
		if not string.match(func.name, "^FUN_") then
			continue
		end

		-- Look for a string referenced from the function body.
		for instruction in func:instructions() do
			local label = nil
			for reference in ghidra.referencesFrom(instruction.address) do
				local data = ghidra.dataAt(reference:getToAddress())
				if data ~= nil and data.text ~= nil and #data.text >= 4 then
					label = data.text
					break
				end
			end

			if label ~= nil then
				local clean = string.gsub(label, "[^%w_]", "_")
				func:rename(`str_{string.sub(clean, 1, 24)}`)
				count += 1
				break
			end
		end
	end
	return count
end)

print(`renamed {renamed} function(s)`)
