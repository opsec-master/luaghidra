-- The LuaGhidra scripting API.
--
--     local ghidra = require("@ghidra")
--
--     for func in ghidra.functions() do
--         print(`{func.name} @ {func.entry}`)
--     end
--
-- Values returned here are the real Ghidra Java objects, so the whole Java API
-- stays available: `func:getBody():getNumAddresses()` works next to `func.size`.
-- Requiring this module also registers the Luau properties and methods listed in
-- @ghidra/extensions.

local internal = require("@ghidra/internal/host")
local types = require("@ghidra/types")

require("@ghidra/extensions")

local ghidra = {}

ghidra.types = types

-- --- Context -------------------------------------------------------------

--- The open program, or nil when none is open.
function ghidra.currentProgram()
	local context = internal.tryContext()
	return context and context:getProgram() or nil
end

--- The open program, raising a clear error when none is open.
function ghidra.program()
	return internal.program()
end

--- The Ghidra tool, or nil when running headless.
function ghidra.tool()
	return internal.context():getTool()
end

--- The task monitor for the running script or console command.
function ghidra.monitor()
	return internal.context():getMonitor()
end

--- The cursor address, or nil when there is none.
function ghidra.currentAddress()
	return internal.context():getCurrentAddress()
end

--- The cursor location, or nil when there is none.
function ghidra.currentLocation()
	return internal.context():getCurrentLocation()
end

--- The current selection, or nil when nothing is selected.
function ghidra.selection()
	local selection = internal.context():getCurrentSelection()
	if selection == nil or selection:isEmpty() then
		return nil
	end
	return selection
end

--- Command-line arguments passed to the script, as a Luau array.
function ghidra.args(): { string }
	return internal.collect(internal.context():getArgs())
end

--- True when running without a GUI.
function ghidra.isHeadless(): boolean
	return internal.context():isHeadless()
end

--- The FlatProgramAPI instance for the current program, as an escape hatch for
--- operations this module does not wrap.
function ghidra.flat()
	return types.FlatProgramAPI(internal.program())
end

--- The GhidraScript running this code, as the escape hatch for the helpers that
--- live on it rather than on the flat API -- the project, the tool state, and
--- the prompts this module has not wrapped.
function ghidra.script()
	return internal.context():getScript()
end

--- Runs another script, by file name, in this script's state.
---
---     ghidra.runScript("AddCommentToProgramScript.java")
---     ghidra.runScript("Report.luau", { "--json" })
function ghidra.runScript(name: string, args: { string }?)
	local script = ghidra.script()
	if args == nil then
		return script:runScript(name)
	end
	local array = java.array(java.import("java.lang.String"), #args)
	for index, value in args do
		array[index] = value
	end
	return script:runScript(name, array)
end

-- --- Output --------------------------------------------------------------

local function joined(...): string
	local parts = table.pack(...)
	for index = 1, parts.n do
		parts[index] = tostring(parts[index])
	end
	return table.concat(parts, "\t", 1, parts.n)
end

--- Writes a line to the Ghidra console. The global `print` does the same thing.
function ghidra.log(...)
	internal.context():println(joined(...))
end

--- Writes a line to the Ghidra console's error stream.
function ghidra.warn(...)
	internal.context():printerr(joined(...))
end

--- Updates the task monitor's status message.
function ghidra.status(message: string)
	internal.context():setStatus(message)
end

-- --- Addresses -----------------------------------------------------------

--- Coerces a string ("00401000" or "ram:00401000"), a number, or an Address
--- into an Address.
---
--- A number is an offset in `space` — an AddressSpace or its name — or in the
--- program's default space when that is omitted, which is what you want on the
--- usual single-space architecture.
function ghidra.address(value, space)
	return internal.context():toAddress(value, space)
end

--- An address space by name, or the default space when no name is given.
function ghidra.addressSpace(name: string?)
	return require("@ghidra/addresses").space(name)
end

--- Every address space the program defines, including overlays.
function ghidra.addressSpaces()
	return require("@ghidra/addresses").spaces()
end

--- An AddressSet spanning `first` through `last`, inclusive. For anything more
--- involved, see `require("@ghidra/addresses")`.
function ghidra.addressSet(first, last)
	return internal.context():toAddressSet(first, last)
end

-- --- Transactions and cancellation ---------------------------------------

--- Runs `body` inside a database transaction on the current program. Commits
--- when it returns, rolls back when it raises, and re-raises either way.
function ghidra.transaction(name: string, body: () -> any): any
	return internal.program():transaction(name, body)
end

--- Raises "script cancelled" when the user has cancelled the task. Iterators
--- returned by this module check this for you.
function ghidra.checkCancelled()
	if internal.context():getMonitor():isCancelled() then
		error("script cancelled", 0)
	end
end

--- A progress reporter over the task monitor.
---
---     local task = ghidra.task("Scanning", { max = program.functionCount })
---     for func in ghidra.functions() do
---         task:step()
---     end
function ghidra.task(name: string, options: { max: number? }?)
	local monitor = internal.context():getMonitor()
	monitor:setMessage(name)
	local max = options and options.max
	if max ~= nil then
		monitor:initialize(max)
	else
		monitor:setIndeterminate(true)
	end

	local task = {}

	function task.step(_, amount: number?)
		if monitor:isCancelled() then
			error("script cancelled", 0)
		end
		monitor:incrementProgress(amount or 1)
	end

	function task.status(_, message: string)
		monitor:setMessage(message)
	end

	function task.checkCancelled(_)
		ghidra.checkCancelled()
	end

	function task.monitor(_)
		return monitor
	end

	return task
end

-- --- Collections ---------------------------------------------------------

--- Turns a Java iterator, iterable, or array into a generic-for iterator.
function ghidra.iterate(source)
	return internal.iterate(source)
end

--- Collects any iterable into a Luau array, optionally stopping at `limit`.
function ghidra.collect(source, limit: number?)
	return internal.collect(source, limit)
end

-- --- Functions -----------------------------------------------------------

--- Iterates functions in address order.
---
--- Options: `forward` (default true), `set` to restrict to an address set,
--- `from` to start at an address, `external` for external functions only.
function ghidra.functions(options: { forward: boolean?, set: any?, from: any?, external: boolean? }?)
	options = options or {}
	local manager = internal.program():getFunctionManager()
	local forward = options.forward ~= false
	if options.external then
		return internal.iterate(manager:getExternalFunctions())
	end
	if options.set ~= nil then
		return internal.iterate(manager:getFunctions(options.set, forward))
	end
	if options.from ~= nil then
		return internal.iterate(manager:getFunctions(ghidra.address(options.from), forward))
	end
	return internal.iterate(manager:getFunctions(forward))
end

--- The function starting exactly at `address`, or nil.
function ghidra.functionAt(address)
	return internal.program():getFunctionManager():getFunctionAt(ghidra.address(address))
end

--- The function whose body covers `address`, or nil.
function ghidra.functionContaining(address)
	return internal.program():getFunctionManager():getFunctionContaining(ghidra.address(address))
end

--- Every function with this name, as a Luau array.
function ghidra.functionsNamed(name: string)
	local out = {}
	local count = 0
	for symbol in ghidra.symbolsNamed(name) do
		local func = ghidra.functionAt(symbol:getAddress())
		if func ~= nil then
			count += 1
			out[count] = func
		end
	end
	return out
end

-- --- Symbols -------------------------------------------------------------

--- Iterates symbols. Options: `dynamic` to include dynamic (default false),
--- `name` to filter by name.
function ghidra.symbols(options: { dynamic: boolean?, name: string? }?)
	options = options or {}
	local table_ = internal.program():getSymbolTable()
	if options.name ~= nil then
		return internal.iterate(table_:getSymbols(options.name))
	end
	return internal.iterate(table_:getAllSymbols(options.dynamic == true))
end

--- Iterates symbols with this name.
function ghidra.symbolsNamed(name: string)
	return internal.iterate(internal.program():getSymbolTable():getSymbols(name))
end

--- The primary symbol at `address`, or nil.
function ghidra.symbolAt(address)
	return internal.program():getSymbolTable():getPrimarySymbol(ghidra.address(address))
end

--- Every symbol at an address, as a Luau array.
function ghidra.symbolsAt(address)
	return internal.collect(internal.program():getSymbolTable():getSymbols(ghidra.address(address)))
end

--- Iterates the program's entry points.
function ghidra.entryPoints()
	return internal.iterate(
		internal.program():getSymbolTable():getExternalEntryPointIterator()
	)
end

--- Creates a label at `address`. Must run inside a transaction.
function ghidra.createLabel(address, name: string, source: string?)
	local SourceType = types.SourceType
	return internal.program():getSymbolTable():createLabel(
		ghidra.address(address),
		name,
		SourceType[source or "USER_DEFINED"]
	)
end

--- Finds or creates a namespace from a "/"-separated path. Creating one
--- requires a transaction.
function ghidra.namespace(path: string, parent)
	return require("@ghidra/symbols").namespace(path, parent)
end

-- --- Listing -------------------------------------------------------------

--- Iterates instructions. Options: `forward` (default true), `set`, `from`.
function ghidra.instructions(options: { forward: boolean?, set: any?, from: any? }?)
	options = options or {}
	local listing = internal.program():getListing()
	local forward = options.forward ~= false
	if options.set ~= nil then
		return internal.iterate(listing:getInstructions(options.set, forward))
	end
	if options.from ~= nil then
		return internal.iterate(listing:getInstructions(ghidra.address(options.from), forward))
	end
	return internal.iterate(listing:getInstructions(forward))
end

--- Iterates defined data. Options: `forward` (default true), `set`, `from`.
function ghidra.data(options: { forward: boolean?, set: any?, from: any? }?)
	options = options or {}
	local listing = internal.program():getListing()
	local forward = options.forward ~= false
	if options.set ~= nil then
		return internal.iterate(listing:getDefinedData(options.set, forward))
	end
	if options.from ~= nil then
		return internal.iterate(listing:getDefinedData(ghidra.address(options.from), forward))
	end
	return internal.iterate(listing:getDefinedData(forward))
end

--- Iterates every defined string in the program. Each item is a Data whose
--- `.text` property holds the decoded string.
function ghidra.strings()
	return internal.iterate(internal.context():definedStrings())
end

function ghidra.instructionAt(address)
	return internal.program():getListing():getInstructionAt(ghidra.address(address))
end

function ghidra.dataAt(address)
	return internal.program():getListing():getDataAt(ghidra.address(address))
end

function ghidra.codeUnitAt(address)
	return internal.program():getListing():getCodeUnitAt(ghidra.address(address))
end

-- --- Neighbours ----------------------------------------------------------
--
-- Walking outwards from an address: the next function, the previous data, the
-- code unit before this one. Each returns nil at the end of the program.

--- The function that starts after `address`, or nil.
function ghidra.functionAfter(address)
	return ghidra.flat():getFunctionAfter(ghidra.address(address))
end

--- The function that starts before `address`, or nil.
function ghidra.functionBefore(address)
	return ghidra.flat():getFunctionBefore(ghidra.address(address))
end

--- The program's first and last functions in address order, or nil.
function ghidra.firstFunction()
	return ghidra.flat():getFirstFunction()
end

function ghidra.lastFunction()
	return ghidra.flat():getLastFunction()
end

--- The defined data after or before `address`, or nil.
function ghidra.dataAfter(address)
	return ghidra.flat():getDataAfter(ghidra.address(address))
end

function ghidra.dataBefore(address)
	return ghidra.flat():getDataBefore(ghidra.address(address))
end

--- The defined data whose extent covers `address`, or nil. Unlike `dataAt`, this
--- finds the data when the address is in the middle of it.
function ghidra.dataContaining(address)
	return internal.program():getListing():getDataContaining(ghidra.address(address))
end

--- The instruction after or before `address`, or nil.
function ghidra.instructionAfter(address)
	return ghidra.flat():getInstructionAfter(ghidra.address(address))
end

function ghidra.instructionBefore(address)
	return ghidra.flat():getInstructionBefore(ghidra.address(address))
end

--- The instruction whose extent covers `address`, or nil.
function ghidra.instructionContaining(address)
	return internal.program():getListing():getInstructionContaining(ghidra.address(address))
end

--- The code unit whose extent covers `address`, or nil.
function ghidra.codeUnitContaining(address)
	return internal.program():getListing():getCodeUnitContaining(ghidra.address(address))
end

--- The address the code unit at `address` refers to, or nil: the target of a
--- call or jump, the data an operand names, or, for a pointer, what it points
--- at. When a code unit refers to more than one address, this is the primary
--- reference -- the one Ghidra shows in the listing.
function ghidra.referencedAddress(address)
	local target = ghidra.address(address)
	local unit = ghidra.codeUnitContaining(target)
	if unit == nil then
		return nil
	end
	for reference in unit:xrefsFrom() do
		if reference:isPrimary() and reference.to.isMemory then
			return reference.to
		end
	end
	local data = ghidra.dataContaining(target)
	if data ~= nil and data:isPointer() then
		local value = data.value
		if value ~= nil and internal.hasMethod(value, "getAddressSpace") then
			return value
		end
	end
	return nil
end

-- --- Comments ------------------------------------------------------------

local COMMENT_TYPES = { EOL = true, PRE = true, POST = true, PLATE = true, REPEATABLE = true }

local function commentType(kind: string?)
	local name = string.upper(kind or "EOL")
	if not COMMENT_TYPES[name] then
		error(`unknown comment type '{name}'; expected EOL, PRE, POST, PLATE, or REPEATABLE`, 3)
	end
	return types.of("ghidra.program.model.listing.CommentType")[name]
end

--- Reads a comment at `address`. `kind` defaults to "EOL".
function ghidra.comment(address, kind: string?): string?
	return internal.program():getListing():getComment(commentType(kind), ghidra.address(address))
end

--- Sets a comment at `address`. Must run inside a transaction.
function ghidra.setComment(address, text: string?, kind: string?)
	internal.program():getListing():setComment(ghidra.address(address), commentType(kind), text)
end

-- --- References ----------------------------------------------------------

--- Iterates references pointing at `address`.
function ghidra.referencesTo(address)
	return internal.iterate(
		internal.program():getReferenceManager():getReferencesTo(ghidra.address(address))
	)
end

--- Iterates references originating at `address`.
function ghidra.referencesFrom(address)
	return internal.iterate(
		internal.program():getReferenceManager():getReferencesFrom(ghidra.address(address))
	)
end

-- --- Focused submodules --------------------------------------------------

local lazy = {
	addresses = "@ghidra/addresses",
	analysis = "@ghidra/analysis",
	blocks = "@ghidra/blocks",
	bookmarks = "@ghidra/bookmarks",
	datatypes = "@ghidra/datatypes",
	decompiler = "@ghidra/decompiler",
	io = "@ghidra/io",
	memory = "@ghidra/memory",
	pcode = "@ghidra/pcode",
	process = "@ghidra/process",
	project = "@ghidra/project",
	references = "@ghidra/references",
	search = "@ghidra/search",
	symbols = "@ghidra/symbols",
	ui = "@ghidra/ui",
}

setmetatable(ghidra, {
	__index = function(self, key: string)
		local module = lazy[key]
		if module == nil then
			return nil
		end
		local value = require(module)
		rawset(self, key, value)
		return value
	end,
})

--- Moves the listing cursor. Accepts an Address, a Function, or a Symbol.
--- Does nothing headless.
function ghidra.goTo(target): boolean
	return require("@ghidra/ui").goTo(target)
end

--- Selects an address set in the listing. Does nothing headless.
function ghidra.setSelection(set)
	require("@ghidra/ui").setSelection(set)
end

--- Decompiles a function. Shorthand for `require("@ghidra/decompiler").decompile`.
function ghidra.decompile(func, options)
	return require("@ghidra/decompiler").decompile(func, options)
end

--- Creates a function at `address`. `body` may be an AddressSetView; when
--- omitted Ghidra works the body out from the code at the entry point. Must run
--- inside a transaction.
function ghidra.createFunction(address, name: string, body)
	local entry = ghidra.address(address)
	return internal.program():getFunctionManager():createFunction(
		name,
		entry,
		body,
		types.SourceType.USER_DEFINED
	)
end

--- Applies a data type at an address. Shorthand for
--- `require("@ghidra/datatypes").apply`. Must run inside a transaction.
function ghidra.createData(address, dataType)
	return require("@ghidra/datatypes").apply(address, dataType)
end

--- Iterates the program's memory blocks.
function ghidra.memoryBlocks()
	return internal.iterate(internal.program():getMemory():getBlocks())
end

--- The memory block containing an address, or nil.
function ghidra.memoryBlockAt(address)
	return internal.program():getMemory():getBlock(ghidra.address(address))
end

-- --- Registers ----------------------------------------------------------

--- The processor register with this name, or nil.
function ghidra.register(name: string)
	return internal.program():getProgramContext():getRegister(name)
end

--- The value a register is known to hold at an address, or nil when the context
--- does not pin one down. Values wider than 53 bits lose precision; use
--- `program:getProgramContext()` directly for those.
function ghidra.registerValue(name: string, address): number?
	local register = ghidra.register(name)
	if register == nil then
		error(`unknown register '{name}'`, 2)
	end
	local value = internal.program():getProgramContext()
		:getRegisterValue(register, ghidra.address(address))
	if value == nil or not value:hasValue() then
		return nil
	end
	return tonumber(tostring(value:getUnsignedValue()))
end

--- The names of the processor's registers, as a Luau array.
function ghidra.registers(): { string }
	local out = {}
	local count = 0
	for register in internal.iterate(internal.program():getProgramContext():getRegisters()) do
		count += 1
		out[count] = register:getName()
	end
	return out
end

-- --- Analysis -----------------------------------------------------------

--- Disassembles at an address. Must run inside a transaction.
function ghidra.disassemble(address): boolean
	return require("@ghidra/analysis").disassemble(address)
end

--- Clears code units. Pass an address, two addresses, or an address set. Must
--- run inside a transaction.
function ghidra.clear(first, last)
	require("@ghidra/analysis").clear(first, last)
end

--- Runs the auto-analyzers and waits for them. Analysis manages its own
--- transactions, so do not call this inside `ghidra.transaction`.
function ghidra.analyze()
	require("@ghidra/analysis").run()
end

-- --- Program state ------------------------------------------------------

--- Saves the program. Only available when it is stored in a project.
function ghidra.save(message: string?)
	local program = internal.program()
	if not program:canSave() then
		error("this program cannot be saved from a script", 2)
	end
	program:save(message or "LuaGhidra script", internal.context():getMonitor())
end

--- Undoes the last transaction, if there is one. Returns whether it undid.
function ghidra.undo(): boolean
	local program = internal.program()
	if not program:canUndo() then
		return false
	end
	program:undo()
	return true
end

--- Redoes the last undone transaction. Returns whether it redid.
function ghidra.redo(): boolean
	local program = internal.program()
	if not program:canRedo() then
		return false
	end
	program:redo()
	return true
end

--- A summary of the program, handy for logging and for reports.
function ghidra.info(): { [string]: any }
	local program = internal.program()
	return {
		name = program.name,
		languageId = program.languageId,
		processor = program.processor,
		bigEndian = program.bigEndian,
		pointerSize = program.pointerSize,
		compiler = program.compilerName,
		format = program.executableFormat,
		path = program.executablePath,
		md5 = program.executableMd5,
		sha256 = program.executableSha256,
		imageBase = tostring(program.imageBase),
		minAddress = tostring(program.minAddress),
		maxAddress = tostring(program.maxAddress),
		functionCount = program.functionCount,
		symbolCount = program.symbolCount,
	}
end

return ghidra
