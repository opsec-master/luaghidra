-- Bookmarks: the notes and markers shown in Ghidra's Bookmarks window.
--
--     local bookmarks = require("@ghidra/bookmarks")
--
--     ghidra.transaction("Mark", function()
--         bookmarks.add(func.entry, "interesting", "Note", "reads the key")
--     end)

local internal = require("@ghidra/internal/host")

local bookmarks = {}

local function manager()
	return internal.program():getBookmarkManager()
end

local function address(value)
	return internal.context():toAddress(value)
end

--- Iterates bookmarks, optionally restricted to one bookmark type such as
--- "Note" or "Analysis".
function bookmarks.all(kind: string?)
	if kind ~= nil then
		return internal.iterate(manager():getBookmarksIterator(kind))
	end
	return internal.iterate(manager():getBookmarksIterator())
end

--- Every bookmark at an address, as a Luau array.
function bookmarks.at(target)
	return internal.collect(manager():getBookmarks(address(target)))
end

--- Adds or replaces a bookmark. `kind` defaults to "Note"; `category` groups
--- bookmarks within a kind. Must run inside a transaction.
function bookmarks.add(target, category: string, kind: string?, comment: string?)
	return manager():setBookmark(
		address(target),
		kind or "Note",
		category,
		comment or ""
	)
end

--- Removes one bookmark. Must run inside a transaction.
function bookmarks.remove(bookmark)
	manager():removeBookmark(bookmark)
end

--- Removes every bookmark of a kind. Must run inside a transaction.
function bookmarks.removeKind(kind: string)
	manager():removeBookmarks(kind)
end

--- The names of the bookmark types this program defines.
function bookmarks.kinds(): { string }
	local out = {}
	local count = 0
	for kind in internal.iterate(manager():getBookmarkTypes()) do
		count += 1
		out[count] = kind:getTypeString()
	end
	return out
end

return bookmarks
