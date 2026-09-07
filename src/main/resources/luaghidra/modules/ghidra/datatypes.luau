-- Data types, and the managers they live in.
--
--     local dt = require("@ghidra/datatypes")
--
--     ghidra.transaction("apply", function()
--         dt.apply(0x402000, "char[16]")
--     end)
--
-- Anywhere a data type is expected you may pass either a DataType or a string
-- in Ghidra's usual notation ("int", "char *", "MyStruct[4]").
--
-- A program can see several data type managers at once: its own, Ghidra's
-- built-in archive, and any file or project archives that are open. Lookups
-- search all of them unless you name one, and applying a type from an archive
-- copies it into the program for you.

local internal = require("@ghidra/internal/host")

local datatypes = {}

-- Archives opened through this module, kept so they show up in managers() and
-- can be closed again.
local opened = {}

local function classes()
	return internal.classes
end

--- The program's own data type manager. Types created here are stored in the
--- program, so this is where writes go.
function datatypes.manager()
	return internal.program():getDataTypeManager()
end

--- Ghidra's built-in archive: the primitive types every program can use.
function datatypes.builtins()
	return classes()["ghidra.program.model.data.BuiltInDataTypeManager"]:getDataTypeManager()
end

--- The tool's data type service, or nil when running headless.
local function service()
	local tool = internal.context():getTool()
	if tool == nil then
		return nil
	end
	local ok, found = pcall(function()
		return tool:getService(classes()["ghidra.app.services.DataTypeManagerService"].class)
	end)
	return if ok then found else nil
end

--- Every data type manager in play, as a Luau array: the program's first, then
--- Ghidra's built-ins, then any open archives.
function datatypes.managers()
	local out = { datatypes.manager(), datatypes.builtins() }
	local seen = { [out[1]:getName()] = true, [out[2]:getName()] = true }

	local function add(manager)
		if manager == nil then
			return
		end
		local name = manager:getName()
		if not seen[name] then
			seen[name] = true
			table.insert(out, manager)
		end
	end

	local tool = service()
	if tool ~= nil then
		for _, manager in internal.collect(tool:getDataTypeManagers()) do
			add(manager)
		end
	end
	for _, manager in opened do
		add(manager)
	end
	return out
end

--- The open archives, without the program's manager or the built-ins.
function datatypes.archives()
	local out = {}
	local all = datatypes.managers()
	for index = 3, #all do
		table.insert(out, all[index])
	end
	return out
end

--- Opens a .gdt file archive and returns its manager. Read-only unless
--- `writable` is true.
---
--- Works headless, unlike the tool's archive list, so a script can rely on it
--- either way. Close it with `closeArchive` when you are done.
function datatypes.openArchive(path: string, writable: boolean?)
	local File = classes()["java.io.File"]
	local FileManager = classes()["ghidra.program.model.data.FileDataTypeManager"]
	local manager = FileManager:openFileArchive(File(path), writable == true)
	table.insert(opened, manager)
	return manager
end

--- Closes an archive opened with `openArchive`.
function datatypes.closeArchive(manager)
	for index, open in opened do
		if open == manager then
			table.remove(opened, index)
			break
		end
	end
	manager:close()
end

-- --- Looking types up ----------------------------------------------------

local function parserFor(manager)
	local Parser = classes()["ghidra.util.data.DataTypeParser"]
	local allowed = classes()["ghidra.util.data.DataTypeParser$AllowedDataTypes"]
	return Parser(manager or datatypes.manager(), nil, nil, allowed.ALL)
end

--- Resolves a data type from a string, or passes a DataType through unchanged.
--- Understands pointers and arrays, e.g. "char *" and "int[4]".
---
--- Searches `manager` when given, otherwise the program's types first and then
--- every other manager, so a name from an open archive resolves too.
function datatypes.resolve(value, manager)
	if value == nil then
		error("expected a data type", 3)
	end
	if typeof(value) ~= "string" then
		return value
	end

	local ok, result = pcall(function()
		return parserFor(manager):parse(value)
	end)
	if ok and result ~= nil then
		return result
	end

	if manager == nil then
		local found = datatypes.find(value)
		if found ~= nil then
			return found
		end
	end
	error(`unknown data type '{value}'`, 3)
end

local function findIn(manager, name: string)
	local matches = java.new(java.import("java.util.ArrayList"))
	manager:findDataTypes(name, matches)
	if matches:isEmpty() then
		return nil
	end
	return matches:get(0)
end

--- The first data type with this name. Searches `manager` when given, otherwise
--- every manager in order. Returns nil when nothing matches.
---
--- Prefer `resolve` unless you specifically want a name lookup without pointer
--- or array syntax.
function datatypes.find(name: string, manager)
	if manager ~= nil then
		return findIn(manager, name)
	end
	for _, candidate in datatypes.managers() do
		local found = findIn(candidate, name)
		if found ~= nil then
			return found
		end
	end
	return nil
end

--- Every data type with this name across every manager, as a Luau array of
--- `{ type = ..., manager = ... }` entries. Useful when archives disagree.
function datatypes.findAll(name: string)
	local out = {}
	for _, manager in datatypes.managers() do
		local matches = java.new(java.import("java.util.ArrayList"))
		manager:findDataTypes(name, matches)
		for _, found in internal.collect(matches) do
			table.insert(out, { type = found, manager = manager })
		end
	end
	return out
end

--- The data type at a full path such as "/MyCategory/MyStruct", or nil.
function datatypes.path(path: string, manager)
	return (manager or datatypes.manager()):getDataType(path)
end

--- Iterates every data type in a manager, defaulting to the program's.
function datatypes.all(manager)
	return internal.iterate((manager or datatypes.manager()):getAllDataTypes())
end

--- Iterates every structure and union in a manager.
function datatypes.composites(manager)
	return internal.iterate((manager or datatypes.manager()):getAllComposites())
end

--- Iterates every function definition in a manager.
function datatypes.functionDefinitions(manager)
	return internal.iterate((manager or datatypes.manager()):getAllFunctionDefinitions())
end

-- --- Categories ----------------------------------------------------------

--- A manager's root category.
function datatypes.rootCategory(manager)
	return (manager or datatypes.manager()):getRootCategory()
end

--- The category at a "/"-separated path, or nil when it does not exist.
function datatypes.category(path: string, manager)
	local CategoryPath = classes()["ghidra.program.model.data.CategoryPath"]
	return (manager or datatypes.manager()):getCategory(CategoryPath(path))
end

--- Iterates every category in a manager, depth first from the root.
function datatypes.categories(manager)
	local pending = { datatypes.rootCategory(manager) }
	return function()
		local category = table.remove(pending)
		if category == nil then
			return nil
		end
		for _, child in internal.collect(category:getCategories()) do
			table.insert(pending, child)
		end
		return category
	end
end

-- --- Moving types into the program ---------------------------------------

--- Copies a data type into the program's manager and returns the stored copy.
--- Types already owned by the program are returned unchanged.
---
--- This is what makes a type from an archive usable in the program. Must run
--- inside a transaction when it actually copies.
function datatypes.import(dataType, conflict: string?)
	local resolved = datatypes.resolve(dataType)
	local manager = datatypes.manager()
	if resolved:getDataTypeManager() == manager then
		return resolved
	end
	local handler =
		classes()["ghidra.program.model.data.DataTypeConflictHandler"][conflict or "DEFAULT_HANDLER"]
	return manager:resolve(resolved, handler)
end

--- Adds a data type to the program's manager, replacing an existing type of the
--- same name. Must run inside a transaction.
function datatypes.store(dataType)
	local handler = classes()["ghidra.program.model.data.DataTypeConflictHandler"].REPLACE_HANDLER
	return datatypes.manager():addDataType(dataType, handler)
end

-- --- Applying types ------------------------------------------------------

--- Iterates every defined data item of a type, which is how you find each place
--- a structure has been laid down.
function datatypes.instances(dataType)
	local wanted = datatypes.resolve(dataType)
	local name = wanted:getName()
	local step = internal.iterate(internal.program():getListing():getDefinedData(true))
	return function()
		for data in step do
			if data:getDataType():getName() == name then
				return data
			end
		end
		return nil
	end
end

--- Applies a data type at an address, replacing whatever is there. A type from
--- an archive is copied into the program first. Must run inside a transaction.
--- Returns the created Data.
function datatypes.apply(address, dataType)
	local target = internal.context():toAddress(address)
	local resolved = datatypes.import(dataType)
	local listing = internal.program():getListing()
	listing:clearCodeUnits(target, target:add(math.max(resolved:getLength(), 1) - 1), false)
	return listing:createData(target, resolved)
end

--- Removes the data defined at an address. Must run inside a transaction.
function datatypes.clear(address)
	local target = internal.context():toAddress(address)
	local data = internal.program():getListing():getDataAt(target)
	if data == nil then
		return false
	end
	internal.program():getListing():clearCodeUnits(target, data:getMaxAddress(), false)
	return true
end

-- --- Building types ------------------------------------------------------

--- Builds a structure and adds it to the program's type manager.
---
---     dt.struct("Header", {
---         { name = "magic", type = "char[4]" },
---         { name = "size", type = "uint", comment = "in bytes" },
---     })
---
--- Must run inside a transaction. Returns the stored DataType.
function datatypes.struct(name: string, fields: { { name: string, type: any, comment: string? } })
	local Structure = classes()["ghidra.program.model.data.StructureDataType"]
	local structure = Structure(name, 0, datatypes.manager())
	for _, field in fields do
		local fieldType = datatypes.resolve(field.type)
		structure:add(fieldType, fieldType:getLength(), field.name, field.comment)
	end
	return datatypes.store(structure)
end

--- Builds a union and adds it to the program's type manager. Must run inside a
--- transaction.
function datatypes.union(name: string, fields: { { name: string, type: any, comment: string? } })
	local Union = classes()["ghidra.program.model.data.UnionDataType"]
	local union = Union(name)
	for _, field in fields do
		local fieldType = datatypes.resolve(field.type)
		union:add(fieldType, fieldType:getLength(), field.name, field.comment)
	end
	return datatypes.store(union)
end

--- Builds an enum and adds it to the program's type manager. `size` is the
--- width in bytes (default 4). Must run inside a transaction.
function datatypes.enum(name: string, values: { [string]: number }, size: number?)
	local Enum = classes()["ghidra.program.model.data.EnumDataType"]
	local root = classes()["ghidra.program.model.data.CategoryPath"].ROOT
	local enumeration = Enum(root, name, size or 4, datatypes.manager())
	for key, value in values do
		enumeration:add(key, value)
	end
	return datatypes.store(enumeration)
end

--- A pointer to a type, sized for the program rather than the 4-byte default a
--- bare PointerDataType would use.
function datatypes.pointer(dataType)
	local Pointer = classes()["ghidra.program.model.data.PointerDataType"]
	return Pointer(datatypes.resolve(dataType), datatypes.manager())
end

--- An array of `count` elements of a type.
function datatypes.array(dataType, count: number)
	local Array = classes()["ghidra.program.model.data.ArrayDataType"]
	local element = datatypes.resolve(dataType)
	return Array(element, count, element:getLength(), datatypes.manager())
end

return datatypes
