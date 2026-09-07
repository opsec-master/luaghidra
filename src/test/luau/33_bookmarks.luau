-- Bookmarks.
local t = require("@test")
local ghidra = require("@ghidra")
local bookmarks = require("@ghidra/bookmarks")

t.assertEqual(#ghidra.collect(bookmarks.all()), 0, "no bookmarks to start")

local mark = ghidra.transaction("bookmark", function()
	return bookmarks.add(0x401000, "entry", "Note", "where execution starts")
end)
t.assertEqual(mark.address.offset, 0x401000, "bookmark.address")
t.assertEqual(mark.kind, "Note", "bookmark.kind")
t.assertEqual(mark.category, "entry", "bookmark.category")
t.assertEqual(mark.comment, "where execution starts", "bookmark.comment")

t.assertEqual(#ghidra.collect(bookmarks.all()), 1, "bookmarks.all")
t.assertEqual(#ghidra.collect(bookmarks.all("Note")), 1, "bookmarks.all filtered by kind")
t.assertEqual(#ghidra.collect(bookmarks.all("Analysis")), 0, "and it really filters")
t.assertEqual(#bookmarks.at(0x401000), 1, "bookmarks.at")
t.assertEqual(#bookmarks.at(0x401100), 0, "bookmarks.at elsewhere")

local kinds = bookmarks.kinds()
t.assertTrue(#kinds > 0, "bookmarks.kinds")

ghidra.transaction("unbookmark", function()
	bookmarks.remove(mark)
end)
t.assertEqual(#ghidra.collect(bookmarks.all()), 0, "bookmarks.remove")

ghidra.transaction("many", function()
	bookmarks.add(0x401000, "a")
	bookmarks.add(0x401100, "b")
end)
t.assertEqual(#ghidra.collect(bookmarks.all()), 2, "the default kind is Note")
ghidra.transaction("purge", function()
	bookmarks.removeKind("Note")
end)
t.assertEqual(#ghidra.collect(bookmarks.all()), 0, "bookmarks.removeKind")

t.finish("bookmarks")
