-- Reading and writing files.
--
--     local io = require("@ghidra/io")
--
--     io.write("/tmp/functions.txt", table.concat(names, "\n"))
--     for line in io.lines("/tmp/addresses.txt") do print(line) end
--
-- Luau ships without a file library, so this fills that gap using the JVM's.
-- A path is a string or the java.io.File a prompt returns; `~` is expanded to
-- the user's home directory.

local internal = require("@ghidra/internal/host")

local io = {}

--- A filesystem path: a string, or the java.io.File a prompt returns.
export type Path = string | any

local function classes()
	return internal.classes
end

local function expand(path): string
	-- ui.askFile and ui.askDirectory hand back java.io.File, so paths from a
	-- prompt work here without being converted first.
	if typeof(path) ~= "string" then
		path = tostring(path)
	end
	local home = classes()["java.lang.System"]:getProperty("user.home")
	if path == "~" then
		return home
	end
	if string.sub(path, 1, 2) == "~/" then
		return home .. string.sub(path, 2)
	end
	return path
end

local function pathOf(path: Path)
	local Path = classes()["java.nio.file.Path"]
	return Path:of(expand(path), java.array(java.import("java.lang.String"), 0))
end

--- Reads a whole file as a string. Raises when it does not exist.
function io.read(path: Path): string
	local Files = classes()["java.nio.file.Files"]
	return Files:readString(pathOf(path))
end

--- Reads a file's lines into a Luau array.
function io.readLines(path: Path): { string }
	local lines = {}
	local count = 0
	for line in string.gmatch(io.read(path) .. "\n", "([^\n]*)\n") do
		count += 1
		lines[count] = line
	end
	-- A trailing newline produces one empty final entry; drop it.
	if count > 0 and lines[count] == "" then
		lines[count] = nil
	end
	return lines
end

--- Iterates a file's lines.
function io.lines(path: Path)
	local lines = io.readLines(path)
	local index = 0
	return function(): string?
		index += 1
		return lines[index]
	end
end

--- Writes a string to a file, replacing it if it exists. Parent directories are
--- created as needed.
function io.write(path: Path, text: string)
	local Files = classes()["java.nio.file.Files"]
	local target = pathOf(path)
	local parent = target:getParent()
	if parent ~= nil then
		Files:createDirectories(parent, java.array(
			java.import("java.nio.file.attribute.FileAttribute"), 0))
	end
	Files:writeString(target, text, java.array(java.import("java.nio.file.OpenOption"), 0))
end

--- Appends a string to a file, creating it if needed.
function io.append(path: Path, text: string)
	local existing = if io.exists(path) then io.read(path) else ""
	io.write(path, existing .. text)
end

--- Whether a path exists.
function io.exists(path: Path): boolean
	local Files = classes()["java.nio.file.Files"]
	return Files:exists(pathOf(path), java.array(java.import("java.nio.file.LinkOption"), 0))
end

--- Whether a path is a directory.
function io.isDirectory(path: Path): boolean
	local Files = classes()["java.nio.file.Files"]
	return Files:isDirectory(pathOf(path), java.array(java.import("java.nio.file.LinkOption"), 0))
end

--- The names of the entries in a directory, as a Luau array.
function io.list(path: Path): { string }
	local file = classes()["java.io.File"](expand(path))
	local names = file:list()
	if names == nil then
		error(`not a directory: {path}`, 2)
	end
	return internal.collect(names)
end

--- Deletes a file. Returns whether anything was removed.
function io.remove(path: Path): boolean
	local Files = classes()["java.nio.file.Files"]
	return Files:deleteIfExists(pathOf(path))
end

--- Creates a directory and any missing parents.
function io.makeDirectory(path: Path)
	local Files = classes()["java.nio.file.Files"]
	Files:createDirectories(pathOf(path), java.array(
		java.import("java.nio.file.attribute.FileAttribute"), 0))
end

--- Encodes a Luau value as JSON. Handles nil, booleans, numbers, strings, and
--- arrays and string-keyed tables of those.
function io.toJson(value, indent: string?): string
	local pieces = {}
	local function emit(text: string)
		table.insert(pieces, text)
	end

	local function encode(item, depth: number)
		local pad = if indent then "\n" .. string.rep(indent, depth + 1) else ""
		local closePad = if indent then "\n" .. string.rep(indent, depth) else ""
		local kind = typeof(item)

		if item == nil then
			emit("null")
		elseif kind == "boolean" then
			emit(tostring(item))
		elseif kind == "number" then
			emit(if item == math.floor(item) and math.abs(item) < 2 ^ 53
				then string.format("%d", item)
				else tostring(item))
		elseif kind == "string" then
			emit(string.format("%q", item))
		elseif kind == "table" then
			if #item > 0 or next(item) == nil then
				emit("[")
				for index, element in item do
					if index > 1 then
						emit(",")
					end
					emit(pad)
					encode(element, depth + 1)
				end
				emit(if #item > 0 then closePad else "")
				emit("]")
			else
				emit("{")
				local first = true
				for key, element in item do
					if not first then
						emit(",")
					end
					first = false
					emit(pad)
					emit(string.format("%q", tostring(key)))
					emit(":")
					if indent then
						emit(" ")
					end
					encode(element, depth + 1)
				end
				emit(closePad)
				emit("}")
			end
		else
			emit(string.format("%q", tostring(item)))
		end
	end

	encode(value, 0)
	return table.concat(pieces)
end

--- Writes a Luau value to a file as JSON.
function io.writeJson(path: Path, value, indent: string?)
	io.write(path, io.toJson(value, indent or "  ") .. "\n")
end

return io
