--@category Luau.Examples
--@description Searches for a byte pattern and bookmarks every hit.

local ghidra = require("@ghidra")
local search = require("@ghidra/search")
local bookmarks = require("@ghidra/bookmarks")
local ui = require("@ghidra/ui")

-- Hex bytes separated by spaces; ?? matches any byte.
local pattern = ui.askString("Find pattern", "Hex bytes (?? for any):", "55 48 89 e5")

local hits = {}
for address in search.pattern(pattern) do
	table.insert(hits, address)
end

if #hits == 0 then
	print(`no match for "{pattern}"`)
	return
end

ghidra.transaction("Bookmark pattern hits", function()
	for _, address in hits do
		local func = ghidra.functionContaining(address)
		local where = if func ~= nil then `{func.name}+{address.offset - func.entry.offset}` else "—"
		bookmarks.add(address, "pattern", "Note", `{pattern} at {where}`)
		print(`{address}  {where}`)
	end
end)

print(`bookmarked {#hits} hit(s)`)
