-- Data type managers: the program's, the built-ins, and file archives.
local t = require("@test")
local ghidra = require("@ghidra")
local dt = require("@ghidra/datatypes")
local io = require("@ghidra/io")

-- The two managers every program has.
local program = dt.manager()
local builtins = dt.builtins()
t.assertEqual(program.kind, "PROGRAM", "the program's manager")
t.assertEqual(builtins.kind, "BUILT_IN", "the built-in archive")
t.assertTrue(builtins.typeCount > 0, "manager.typeCount")
t.assertTrue(program ~= builtins, "and they are different managers")

local managers = dt.managers()
t.assertTrue(#managers >= 2, "dt.managers lists at least both")
t.assertEqual(managers[1].name, program.name, "the program's manager comes first")
t.assertEqual(#dt.archives(), 0, "no archives are open yet")

-- Built-in types are found even though they are not in the program.
local byteType = dt.find("byte")
t.assertTrue(byteType ~= nil, "dt.find reaches the built-ins")
t.assertEqual(byteType.manager.kind, "BUILT_IN", "dataType.manager says where it came from")
t.assertEqual(byteType.length, 1, "dataType.length")
t.assertTrue(#byteType.description > 0, "dataType.description")

-- Types created in the program belong to the program's manager.
ghidra.transaction("types", function()
	dt.struct("Local", { { name = "a", type = "int" } })
end)
local localType = dt.find("Local")
t.assertEqual(localType.manager.kind, "PROGRAM", "a program type knows its manager")
t.assertEqual(localType.path, "/Local", "dataType.path")
t.assertEqual(localType.category, "/", "dataType.category")
t.assertEqual(localType.componentCount, 1, "composite.componentCount")
t.assertEqual(localType:fields()[1].fieldName, "a", "composite:fields()")
t.assertEqual(localType:fields()[1].offset, 0, "component.offset")
t.assertEqual(localType:fields()[1].typeName, "int", "component.typeName")

-- Searching a single manager, and searching them all.
t.assertEqual(dt.find("Local", builtins), nil, "a program type is not in the built-ins")
t.assertTrue(dt.find("byte", builtins) ~= nil, "dt.find scoped to one manager")
t.assertTrue(#dt.findAll("byte") >= 1, "dt.findAll reports every match")
t.assertEqual(dt.findAll("byte")[1].manager.kind, "BUILT_IN", "with the manager it came from")

-- Categories.
local root = dt.rootCategory()
t.assertTrue(root:isRoot(), "the root category")
t.assertEqual(root.path, "/", "category.path")
t.assertTrue(#root:types() >= 1, "category:types()")
t.assertEqual(root.manager.kind, "PROGRAM", "category.manager")
local count = 0
for _ in dt.categories() do
	count += 1
end
t.assertTrue(count >= 1, "dt.categories walks the tree")

-- A file archive, created and then reopened through the module.
local archivePath = java.import("java.lang.System"):getProperty("java.io.tmpdir")
	.. "/luaghidra-test.gdt"
io.remove(archivePath)

local FileManager = java.import("ghidra.program.model.data.FileDataTypeManager")
local File = java.import("java.io.File")
local archive = FileManager:createFileArchive(File(archivePath))
local transaction = archive:startTransaction("build")
local Structure = java.import("ghidra.program.model.data.StructureDataType")
local shape = Structure("FromArchive", 0, archive)
shape:add(dt.resolve("int"), 4, "x", nil)
shape:add(dt.resolve("int"), 4, "y", nil)
archive:addDataType(shape, java.import("ghidra.program.model.data.DataTypeConflictHandler").REPLACE_HANDLER)
archive:endTransaction(transaction, true)
archive:save()
archive:close()

local opened = dt.openArchive(archivePath)
t.assertEqual(opened.kind, "FILE", "an opened archive reports its kind")
t.assertEqual(#dt.archives(), 1, "dt.archives lists it")
t.assertEqual(#dt.managers(), 3, "and dt.managers includes it")

-- The archive's type is now findable, and resolvable by name.
local fromArchive = dt.find("FromArchive")
t.assertTrue(fromArchive ~= nil, "dt.find searches open archives")
t.assertEqual(fromArchive.manager.kind, "FILE", "and reports the archive as its manager")
t.assertEqual(fromArchive.length, 8, "the archive type's length")
t.assertTrue(dt.resolve("FromArchive") ~= nil, "dt.resolve falls back to a name search")

-- Applying it copies it into the program.
ghidra.transaction("apply archive type", function()
	dt.apply(0x401400, "FromArchive")
end)
local applied = ghidra.dataAt(0x401400)
t.assertEqual(applied.typeName, "FromArchive", "the archive type was applied")
t.assertEqual(applied.dataType.manager.kind, "PROGRAM", "and copied into the program")
t.assertTrue(dt.find("FromArchive", dt.manager()) ~= nil, "the program now has its own copy")

dt.closeArchive(opened)
t.assertEqual(#dt.archives(), 0, "dt.closeArchive")
io.remove(archivePath)

-- Type constructors.
t.assertEqual(dt.pointer("int").length, 8, "dt.pointer")
t.assertEqual(dt.array("int", 4).length, 16, "dt.array")
ghidra.transaction("union", function()
	local either = dt.union("Either", {
		{ name = "asInt", type = "int" },
		{ name = "asBytes", type = "char[8]" },
	})
	t.assertEqual(either.length, 8, "dt.union is as wide as its widest field")
end)

t.finish("datatype managers")
