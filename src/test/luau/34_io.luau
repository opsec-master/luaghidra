-- File reading and writing, which Luau has no library for.
local t = require("@test")
local io = require("@ghidra/io")

local dir = java.import("java.lang.System"):getProperty("java.io.tmpdir")
	.. "/luaghidra-io-test"
local file = `{dir}/notes.txt`

io.makeDirectory(dir)
t.assertTrue(io.isDirectory(dir), "io.makeDirectory")

io.write(file, "first\nsecond\n")
t.assertTrue(io.exists(file), "io.exists")
t.assertEqual(io.read(file), "first\nsecond\n", "io.read")

local lines = io.readLines(file)
t.assertEqual(#lines, 2, "io.readLines drops the trailing blank")
t.assertEqual(lines[2], "second", "and keeps the content")

local walked = {}
for line in io.lines(file) do
	table.insert(walked, line)
end
t.assertEqual(table.concat(walked, "|"), "first|second", "io.lines")

io.append(file, "third\n")
t.assertEqual(#io.readLines(file), 3, "io.append")

-- Writing into a directory that does not exist yet creates it.
io.write(`{dir}/nested/deep.txt`, "x")
t.assertEqual(io.read(`{dir}/nested/deep.txt`), "x", "io.write creates parents")

local names = io.list(dir)
t.assertTrue(#names >= 2, "io.list")

-- JSON.
t.assertEqual(io.toJson({ 1, 2, 3 }), "[1,2,3]", "toJson: array")
t.assertEqual(io.toJson({ name = "main" }), '{"name":"main"}', "toJson: object")
t.assertEqual(io.toJson(true), "true", "toJson: boolean")
t.assertEqual(io.toJson("hi"), '"hi"', "toJson: string")
t.assertEqual(io.toJson({}), "[]", "toJson: empty table")
t.assertEqual(io.toJson({ 1.5 }), "[1.5]", "toJson: fractional number")

io.writeJson(`{dir}/data.json`, { functions = { "main", "helper" }, count = 2 })
local written = io.read(`{dir}/data.json`)
t.assertTrue(string.find(written, "\"count\"") ~= nil, "writeJson wrote the key")
t.assertTrue(string.find(written, "helper") ~= nil, "and the nested array")

t.assertTrue(io.remove(file), "io.remove")
t.assertTrue(not io.exists(file), "and the file is gone")
t.assertTrue(not io.remove(file), "removing a missing file reports false")

local missing = pcall(function()
	return io.read(`{dir}/not-there.txt`)
end)
t.assertTrue(not missing, "reading a missing file raises")

-- Clean up.
io.remove(`{dir}/nested/deep.txt`)
-- A java.io.File works anywhere a path does, so what ui.askFile returns can be
-- passed straight to io.write.
local File = java.import("java.io.File")
local asFile = java.new(File, `{dir}/from-file-object.txt`)
io.write(asFile, "written through a File")
t.assertTrue(io.exists(asFile), "io.exists accepts a java.io.File")
t.assertEqual(io.read(asFile), "written through a File", "io.write accepts a java.io.File")
io.remove(asFile)

io.remove(`{dir}/nested`)
io.remove(`{dir}/data.json`)
io.remove(dir)

t.finish("io")
