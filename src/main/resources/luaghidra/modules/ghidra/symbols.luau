-- Symbols, labels, and namespaces.
--
--     local symbols = require("@ghidra/symbols")
--
--     ghidra.transaction("Label", function()
--         local ns = symbols.namespace("MyLib/Internals")
--         symbols.createLabel(0x401000, "init", ns)
--     end)

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")

local symbols = {}

local function table_()
	return internal.program():getSymbolTable()
end

local function address(value)
	return internal.context():toAddress(value)
end

--- Iterates symbols. Options: `dynamic` to include dynamic symbols (default
--- false), `name` to filter by name, `namespace` to list one namespace, `set`
--- to restrict to an address set.
function symbols.all(options: { dynamic: boolean?, name: string?, namespace: any?, set: any? }?)
	options = options or {}
	if options.name ~= nil then
		return internal.iterate(table_():getSymbols(options.name))
	end
	if options.namespace ~= nil then
		return internal.iterate(table_():getSymbols(options.namespace))
	end
	if options.set ~= nil then
		-- The symbol table iterates from an address rather than over a set, so
		-- the set is applied as a filter and the walk stops past its end.
		local set = options.set
		local last = set:getMaxAddress()
		local step = internal.iterate(table_():getSymbolIterator(set:getMinAddress(), true))
		return function()
			for symbol in step do
				local at = symbol:getAddress()
				if set:contains(at) then
					return symbol
				end
				if at > last then
					return nil
				end
			end
			return nil
		end
	end
	return internal.iterate(table_():getAllSymbols(options.dynamic == true))
end

--- Iterates symbols with this name, in any namespace.
function symbols.named(name: string)
	return internal.iterate(table_():getSymbols(name))
end

--- The primary symbol at an address, or nil.
function symbols.at(target)
	return table_():getPrimarySymbol(address(target))
end

--- Every symbol at an address, as a Luau array.
function symbols.allAt(target)
	return internal.collect(table_():getSymbols(address(target)))
end

--- Iterates the program's entry points.
function symbols.entryPoints()
	return internal.iterate(table_():getExternalEntryPointIterator())
end

--- Creates a label. Must run inside a transaction.
function symbols.createLabel(target, name: string, namespace, source: string?)
	return table_():createLabel(
		address(target),
		name,
		namespace,
		support.sourceType(source)
	)
end

--- Removes a label. Must run inside a transaction.
function symbols.remove(symbol): boolean
	return table_():removeSymbolSpecial(symbol)
end

--- Finds or creates a namespace from a "/"-separated path, relative to the
--- global namespace unless `parent` is given. Creating requires a transaction.
function symbols.namespace(path: string, parent)
	local current = parent or internal.program():getGlobalNamespace()
	for part in string.gmatch(path, "[^/]+") do
		local existing = table_():getNamespace(part, current)
		if existing == nil then
			existing = table_():createNameSpace(current, part, support.sourceType())
		end
		current = existing
	end
	return current
end

--- The namespace at a "/"-separated path, or nil when it does not exist.
function symbols.findNamespace(path: string, parent)
	local current = parent or internal.program():getGlobalNamespace()
	for part in string.gmatch(path, "[^/]+") do
		current = table_():getNamespace(part, current)
		if current == nil then
			return nil
		end
	end
	return current
end

--- The program's global namespace.
function symbols.global()
	return internal.program():getGlobalNamespace()
end

return symbols
