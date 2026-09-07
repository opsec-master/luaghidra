-- Commonly used Ghidra Java classes, imported on first access.
--
--     local types = require("@ghidra/types")
--     func:setName("main", types.SourceType.USER_DEFINED)
--
-- Anything not listed here is still reachable:
--
--     local MyClass = types.of("ghidra.some.package.MyClass")

local internal = require("@ghidra/internal/host")

local NAMES = {
	-- addresses
	Address = "ghidra.program.model.address.Address",
	AddressSet = "ghidra.program.model.address.AddressSet",
	AddressSpace = "ghidra.program.model.address.AddressSpace",
	GenericAddress = "ghidra.program.model.address.GenericAddress",

	-- listing
	CodeUnit = "ghidra.program.model.listing.CodeUnit",
	Data = "ghidra.program.model.listing.Data",
	Function = "ghidra.program.model.listing.Function",
	Instruction = "ghidra.program.model.listing.Instruction",
	Listing = "ghidra.program.model.listing.Listing",
	Parameter = "ghidra.program.model.listing.Parameter",
	Program = "ghidra.program.model.listing.Program",
	Variable = "ghidra.program.model.listing.Variable",

	-- symbols and references
	Namespace = "ghidra.program.model.symbol.Namespace",
	RefType = "ghidra.program.model.symbol.RefType",
	Reference = "ghidra.program.model.symbol.Reference",
	SourceType = "ghidra.program.model.symbol.SourceType",
	Symbol = "ghidra.program.model.symbol.Symbol",
	SymbolType = "ghidra.program.model.symbol.SymbolType",
	SymbolUtilities = "ghidra.program.model.symbol.SymbolUtilities",

	-- memory
	Memory = "ghidra.program.model.mem.Memory",
	MemoryBlock = "ghidra.program.model.mem.MemoryBlock",

	-- data types
	DataType = "ghidra.program.model.data.DataType",
	DataTypeManager = "ghidra.program.model.data.DataTypeManager",
	PointerDataType = "ghidra.program.model.data.PointerDataType",
	StringDataInstance = "ghidra.program.model.data.StringDataInstance",
	StructureDataType = "ghidra.program.model.data.StructureDataType",

	-- decompiler
	ClangTokenGroup = "ghidra.app.decompiler.ClangTokenGroup",
	DecompInterface = "ghidra.app.decompiler.DecompInterface",
	DecompileOptions = "ghidra.app.decompiler.DecompileOptions",
	DecompileResults = "ghidra.app.decompiler.DecompileResults",
	HighFunction = "ghidra.program.model.pcode.HighFunction",

	-- pcode
	PcodeOp = "ghidra.program.model.pcode.PcodeOp",
	Varnode = "ghidra.program.model.pcode.Varnode",

	-- misc
	FlatProgramAPI = "ghidra.program.flatapi.FlatProgramAPI",
	TaskMonitor = "ghidra.util.task.TaskMonitor",
}

local types = {}

--- Imports any Java class by its fully qualified name.
function types.of(name: string)
	return internal.classes[name]
end

return setmetatable(types, {
	__index = function(_, key: string)
		local name = NAMES[key]
		if name == nil then
			error(
				`unknown Ghidra type '{key}'; use types.of("fully.qualified.ClassName") for classes that are not listed`,
				2
			)
		end
		return internal.classes[name]
	end,
})
