-- Transactions, renaming, comments, and memory writes.
local t = require("@test")
local ghidra = require("@ghidra")
local memory = require("@ghidra/memory")

local main = ghidra.functionAt(0x401000)

-- A transaction that succeeds commits.
ghidra.transaction("rename", function()
	main:rename("entry_point")
end)
t.assertEqual(ghidra.functionAt(0x401000).name, "entry_point", "rename committed")

-- Assigning the property does the same thing.
ghidra.transaction("rename back", function()
	main.name = "main"
end)
t.assertEqual(main.name, "main", "property assignment renames")

-- A transaction that raises rolls back and re-raises.
local ok, err = pcall(function()
	ghidra.transaction("failing", function()
		main:rename("should_not_stick")
		error("boom")
	end)
end)
t.assertTrue(not ok, "a failing transaction re-raises")
t.assertTrue(string.find(tostring(err), "boom") ~= nil, "the original error survives")
t.assertEqual(main.name, "main", "a failing transaction rolls back")

-- Comments.
ghidra.transaction("comment", function()
	ghidra.setComment(0x401000, "the entry point", "EOL")
end)
t.assertEqual(ghidra.comment(0x401000, "EOL"), "the entry point", "comment round-trip")

local badKind = pcall(function()
	ghidra.comment(0x401000, "NOPE")
end)
t.assertTrue(not badKind, "an unknown comment type is rejected")

-- Memory reads and writes, in the filler past the two functions.
local scratch = 0x401400
t.assertEqual(memory.u8(scratch), 0x90, "memory.u8 reads the fill byte")
t.assertEqual(memory.u8(0x401000), 0x55, "memory.u8 reads real code")
ghidra.transaction("write", function()
	memory.write(scratch, "\xde\xad\xbe\xef")
end)
t.assertEqual(memory.u8(scratch), 0xde, "memory.write wrote the first byte")
t.assertEqual(memory.u32(scratch), 0xefbeadde, "memory.u32 uses program endianness")
t.assertEqual(memory.hex(memory.read(scratch, 4)), "deadbeef", "memory.hex")
t.assertEqual(memory.string(scratch, 2), "\xde\xad", "memory.string")

-- Where an address came from in the file on disk. The scratch program is built
-- in memory rather than loaded, so there is nothing to report; the point is that
-- asking is answered rather than raising.
local offset = memory.fileOffset(0x401000)
t.assertTrue(offset == nil or type(offset) == "number", "memory.fileOffset")
local name = memory.fileName(0x401000)
t.assertTrue(name == nil or type(name) == "string", "memory.fileName")
t.assertEqual(#memory.addressesForFileOffset(0), 0,
	"memory.addressesForFileOffset on a program with no file")

t.finish("ghidra writes")
