-- Cross-references: querying them, and creating or removing them.
--
--     local refs = require("@ghidra/references")
--
--     for reference in refs.to(func.entry) do
--         print(reference.from, reference.kind)
--     end

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")

local references = {}

local function manager()
	return internal.program():getReferenceManager()
end

local function address(value)
	return internal.context():toAddress(value)
end

--- The RefType with this name, e.g. "DATA", "READ", "UNCONDITIONAL_CALL".
function references.type(name: string)
	local RefType = internal.classes["ghidra.program.model.symbol.RefType"]
	local value = RefType[name]
	if value == nil then
		error(`unknown reference type '{name}'`, 2)
	end
	return value
end

--- Iterates references pointing at an address.
function references.to(target)
	return internal.iterate(manager():getReferencesTo(address(target)))
end

--- Iterates references originating at an address.
function references.from(source)
	return internal.iterate(manager():getReferencesFrom(address(source)))
end

--- How many references point at an address.
function references.countTo(target): number
	return manager():getReferenceCountTo(address(target))
end

--- Iterates only the call references pointing at an address, which is the usual
--- way to find a function's callers along with their call sites.
function references.callsTo(target)
	local step = references.to(target)
	return function()
		for reference in step do
			if reference:getReferenceType():isCall() then
				return reference
			end
		end
		return nil
	end
end

--- Adds a memory reference. `kind` names a RefType and defaults to "DATA";
--- `operand` is 1-based, or nil for a mnemonic reference; `sourceType` names a
--- SourceType and defaults to "USER_DEFINED", which is what a script marking up
--- a program by hand wants -- pass "ANALYSIS" for references a script worked out
--- the way an analyzer would. Must run inside a transaction.
function references.add(source, target, kind: string?, operand: number?, sourceType: string?)
	local index = if operand ~= nil then operand - 1 else -1
	return manager():addMemoryReference(
		address(source),
		address(target),
		references.type(kind or "DATA"),
		support.sourceType(sourceType),
		index
	)
end

--- Removes one reference. Must run inside a transaction.
function references.remove(reference)
	manager():delete(reference)
end

--- Removes every reference originating at an address. Must run inside a
--- transaction.
function references.removeAllFrom(source)
	manager():removeAllReferencesFrom(address(source))
end

--- Removes every reference pointing at an address. Must run inside a
--- transaction.
function references.removeAllTo(target)
	manager():removeAllReferencesTo(address(target))
end

--- Marks a reference as the primary one for its operand. Must run inside a
--- transaction.
function references.setPrimary(reference, primary: boolean?)
	manager():setPrimary(reference, primary ~= false)
end

return references
