-- Disassembly, analysis, and clearing.
--
--     local analysis = require("@ghidra/analysis")
--
--     ghidra.transaction("Disassemble", function()
--         analysis.disassemble(0x401000)
--         analysis.createFunction(0x401000, "entry")
--     end)
--     analysis.run()

local internal = require("@ghidra/internal/host")
local analysis = {}

local function flat()
	return internal.classes["ghidra.program.flatapi.FlatProgramAPI"](internal.program())
end

local function address(value)
	return internal.context():toAddress(value)
end

--- Disassembles at an address. Must run inside a transaction.
function analysis.disassemble(target): boolean
	return flat():disassemble(address(target))
end

--- Clears code units. Pass an address, two addresses, or an address set. Must
--- run inside a transaction.
function analysis.clear(first, last)
	local api = flat()
	if last ~= nil then
		api:clearListing(address(first), address(last))
	elseif typeof(first) == "userdata" and internal.hasMethod(first, "getNumAddressRanges") then
		api:clearListing(first)
	else
		api:clearListing(address(first))
	end
end

--- Creates a function at an address, letting Ghidra work out the body. Must run
--- inside a transaction.
function analysis.createFunction(target, name: string?)
	return flat():createFunction(address(target), name)
end

--- Removes the function at an address. Must run inside a transaction.
function analysis.removeFunction(target)
	flat():removeFunctionAt(address(target))
end

--- Runs the auto-analyzers over everything and waits for them to finish.
---
--- Analysis manages its own transactions, so this must NOT be called from
--- inside `ghidra.transaction`.
function analysis.run()
	flat():analyzeAll(internal.program())
end

--- Runs the auto-analyzers over whatever changed since the last analysis, and
--- waits. Like `run`, this manages its own transactions.
function analysis.runChanges()
	flat():analyzeChanges(internal.program())
end

--- The AutoAnalysisManager, for scheduling individual analyzers.
function analysis.manager()
	local Manager = internal.classes["ghidra.app.plugin.core.analysis.AutoAnalysisManager"]
	return Manager:getAnalysisManager(internal.program())
end

--- Queues the given address set for re-analysis. Returns immediately.
function analysis.reanalyze(set)
	analysis.manager():reAnalyzeAll(set)
end

--- Sets the byte-level fall-through and creates an instruction flow override.
--- Must run inside a transaction.
function analysis.setFallThrough(target, destination)
	local instruction = internal.program():getListing():getInstructionAt(address(target))
	if instruction == nil then
		error(`no instruction at {address(target)}`, 2)
	end
	instruction:setFallThrough(if destination ~= nil then address(destination) else nil)
end

--- Marks a function as a thunk of another. Must run inside a transaction.
function analysis.setThunk(func, target)
	func:setThunkedFunction(target)
end

-- --- Analyzer options -----------------------------------------------------

local function analyzerOptions()
	local Program = internal.classes["ghidra.program.model.listing.Program"]
	return internal.program():getOptions(Program.ANALYSIS_PROPERTIES)
end

--- Every analyzer option, as a table of name to current value. Names are the
--- ones Ghidra shows in Analysis Options, such as "Stack" or
--- "ASCII Strings.Minimum String Length".
function analysis.options(): { [string]: string }
	local options = analyzerOptions()
	local out = {}
	for name in internal.iterate(options:getOptionNames()) do
		out[name] = options:getValueAsString(name)
	end
	return out
end

--- One analyzer option's current value, as a string, or nil when there is no
--- such option.
function analysis.option(name: string): string?
	local options = analyzerOptions()
	if not options:contains(name) then
		return nil
	end
	return options:getValueAsString(name)
end

--- The description Ghidra shows for an analyzer option, or nil.
function analysis.optionDescription(name: string): string?
	local options = analyzerOptions()
	if not options:contains(name) then
		return nil
	end
	return options:getDescription(name)
end

--- Sets an analyzer option. Booleans, numbers, and strings are all accepted;
--- the option's own type decides how the value is stored. Must run inside a
--- transaction.
---
---     ghidra.transaction("Configure", function()
---         analysis.setOption("Stack", false)
---         analysis.setOption("ASCII Strings.Minimum String Length", "LEN_8")
---     end)
function analysis.setOption(name: string, value)
	local options = analyzerOptions()
	if not options:contains(name) then
		error(`no analyzer option named {name}`, 2)
	end
	if typeof(value) == "boolean" then
		options:setBoolean(name, value)
	elseif typeof(value) == "number" then
		if value % 1 == 0 then
			options:setInt(name, value)
		else
			options:setDouble(name, value)
		end
	else
		options:setString(name, tostring(value))
	end
end

--- Restores analyzer options to their defaults: the ones named, or all of them.
--- Must run inside a transaction.
function analysis.resetOptions(names: { string }?)
	local options = analyzerOptions()
	if names == nil then
		for name in internal.iterate(options:getOptionNames()) do
			options:restoreDefaultValue(name)
		end
		return
	end
	for _, name in names do
		options:restoreDefaultValue(name)
	end
end

-- Demangling first asks for the program's own demanglers, which respect its
-- compiler spec, and falls back to Ghidra's general demangler when the program
-- has none that apply.
local function demangled(name: string)
	local DemanglerUtil = internal.classes["ghidra.app.util.demangler.DemanglerUtil"]

	local ok, results = pcall(function()
		return DemanglerUtil:demangle(internal.program(), name, nil)
	end)
	if ok and results ~= nil then
		local first = internal.collect(results)[1]
		if first ~= nil then
			return first
		end
	end

	local plainOk, plain = pcall(function()
		return DemanglerUtil:demangle(name)
	end)
	return if plainOk then plain else nil
end

--- Demangles a symbol name into a readable signature, or nil when the name is
--- not mangled in a scheme Ghidra recognizes.
---
---     analysis.demangle("_ZN3foo3barEv")  --> "__rustcall foo::bar(void)"
function analysis.demangle(name: string): string?
	local object = demangled(name)
	return if object ~= nil then object:getSignature() else nil
end

--- The demangled short name, without namespace or parameters, or nil.
function analysis.demangledName(name: string): string?
	local object = demangled(name)
	return if object ~= nil then object:getName() else nil
end

return analysis
