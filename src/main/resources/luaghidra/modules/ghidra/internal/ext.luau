-- Shared helpers for the extension modules.

local internal = require("@ghidra/internal/host")

local support = {}

--- Builds an extension property from a getter and an optional setter.
function support.property(get, set)
	return { get = get, set = set }
end

--- Looks up a SourceType by name, defaulting to USER_DEFINED.
function support.sourceType(name: string?)
	return internal.classes["ghidra.program.model.symbol.SourceType"][name or "USER_DEFINED"]
end

--- Resolves a data type from a string or passes a DataType through. Required
--- lazily so the extension modules do not depend on @ghidra/datatypes at load.
function support.dataType(value)
	return require("@ghidra/datatypes").resolve(value)
end

return support
