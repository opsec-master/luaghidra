-- Decompiler P-code: the register-transfer form Ghidra's analysis works on.
--
--     local pcode = require("@ghidra/pcode")
--
--     local high = pcode.high(func)
--     for op in pcode.ops(high) do
--         print(op.mnemonic, op.output, #op:inputs())
--     end
--
-- Call sites carry their arguments here, which is where most analysis starts:
--
--     for call in pcode.callsTo("sprintf") do
--         print(call.at, pcode.stringOf(call.args[2]))
--     end
--
-- Raw (pre-decompiler) P-code for a single instruction is `instruction:pcode()`.

local internal = require("@ghidra/internal/host")

local pcode = {}

--- The decompiler's HighFunction for a function, or nil when it would not
--- decompile.
function pcode.high(func, options)
	local result = require("@ghidra/decompiler").decompile(func, options)
	return if result.ok then result.highFunction else nil
end

--- Iterates the P-code operations of a HighFunction, or of a function (which is
--- decompiled first).
function pcode.ops(target, options)
	local high = if internal.hasMethod(target, "getPcodeOps") then target else pcode.high(target, options)
	if high == nil then
		return function()
			return nil
		end
	end
	return internal.iterate(high:getPcodeOps())
end

--- Iterates a HighFunction's basic blocks.
function pcode.blocks(high)
	return internal.iterate(high:getBasicBlocks())
end

--- The decompiler's view of a function's local variables and parameters, as a
--- Luau array of HighSymbols.
function pcode.symbols(high)
	return internal.collect(high:getLocalSymbolMap():getSymbols())
end

--- The decompiler's parameters for a function, as a Luau array.
function pcode.parameters(high)
	local map = high:getLocalSymbolMap()
	local out = table.create(map:getNumParams())
	for index = 0, map:getNumParams() - 1 do
		out[index + 1] = map:getParam(index)
	end
	return out
end

-- --- Call sites -----------------------------------------------------------

export type Call = {
	at: any,
	target: any,
	targetFunction: any,
	args: { any },
	op: any,
	caller: any,
	indirect: boolean,
}

local function callOf(op, caller): Call?
	local mnemonic = op:getMnemonic()
	local indirect = mnemonic == "CALLIND"
	if mnemonic ~= "CALL" and not indirect then
		return nil
	end
	local inputs = op:inputs()
	local args = table.create(math.max(#inputs - 1, 0))
	for index = 2, #inputs do
		args[index - 1] = inputs[index]
	end
	local destination = inputs[1]
	local target = if destination ~= nil and not indirect then destination:getAddress() else nil
	return {
		at = op:getSeqnum():getTarget(),
		target = target,
		targetFunction = if target ~= nil
			then internal.program():getFunctionManager():getFunctionAt(target)
			else nil,
		args = args,
		op = op,
		caller = caller,
		indirect = indirect,
	}
end

--- Iterates the calls a function makes, with the arguments the decompiler
--- worked out for each one. Options are passed on to the decompiler.
---
---     for call in pcode.calls(func) do
---         print(call.at, call.targetFunction and call.targetFunction.name, #call.args)
---     end
function pcode.calls(func, options)
	local step = pcode.ops(func, options)
	local caller = if internal.hasMethod(func, "getEntryPoint") then func else nil
	return function(): Call?
		while true do
			local op = step()
			if op == nil then
				return nil
			end
			local call = callOf(op, caller)
			if call ~= nil then
				return call
			end
		end
	end
end

--- Iterates every call site of a function, from the callers' point of view, so
--- each call carries its arguments. `target` may be a Function, an address, or a
--- name.
---
--- Each calling function is decompiled once, which is the expensive part; pass
--- `{ timeout = n }` to bound each decompilation.
function pcode.callsTo(target, options)
	local func = target
	if type(target) == "string" then
		func = require("@ghidra").functionsNamed(target)[1]
		if func == nil then
			error(`no function named {target}`, 2)
		end
	elseif not internal.hasMethod(target, "getEntryPoint") then
		func = require("@ghidra").functionAt(target)
		if func == nil then
			error("no function at that address", 2)
		end
	end

	local entry = tostring(func:getEntryPoint())
	local callers = {}
	local order = {}
	for reference in func:xrefs() do
		local caller = internal.program():getFunctionManager()
			:getFunctionContaining(reference:getFromAddress())
		if caller ~= nil and callers[tostring(caller:getEntryPoint())] == nil then
			callers[tostring(caller:getEntryPoint())] = caller
			table.insert(order, caller)
		end
	end

	local index = 0
	local step = nil
	return function(): Call?
		while true do
			if step == nil then
				index += 1
				if order[index] == nil then
					return nil
				end
				step = pcode.calls(order[index], options)
			end
			local call = step()
			if call == nil then
				step = nil
				continue
			end
			if call.target ~= nil and tostring(call.target) == entry then
				return call
			end
		end
	end
end

-- --- Reading values off varnodes -------------------------------------------

local CONSTANT_FORWARDING = {
	COPY = true,
	CAST = true,
	INT_ZEXT = true,
	INT_SEXT = true,
	INDIRECT = true,
}

local CONSTANT_SUM = {
	PTRSUB = true,
	PTRADD = true,
	INT_ADD = true,
}

--- The constant a varnode holds, following the definitions the decompiler
--- builds for an address or an immediate: a constant, a copy or cast of one, or
--- a sum of constants such as the PTRSUB the decompiler emits for a global.
--- Returns nil when the value is not constant.
function pcode.constant(varnode, depth: number?): number?
	if varnode == nil then
		return nil
	end
	if varnode:isConstant() then
		return varnode:getOffset()
	end
	if varnode:isAddress() then
		return varnode:getOffset()
	end
	local remaining = depth or 8
	if remaining <= 0 then
		return nil
	end
	local definition = varnode:getDef()
	if definition == nil then
		return nil
	end
	local mnemonic = definition:getMnemonic()
	local inputs = definition:inputs()
	if CONSTANT_FORWARDING[mnemonic] then
		return pcode.constant(inputs[1], remaining - 1)
	end
	if CONSTANT_SUM[mnemonic] then
		local total = 0
		for _, input in inputs do
			local value = pcode.constant(input, remaining - 1)
			if value == nil then
				return nil
			end
			total += value
		end
		return total
	end
	return nil
end

--- The address a varnode points at, or nil when it does not hold one.
function pcode.addressOf(varnode)
	local value = pcode.constant(varnode)
	if value == nil then
		return nil
	end
	local ok, address = pcall(function()
		return internal.context():toAddress(value)
	end)
	return if ok then address else nil
end

--- The NUL-terminated string a varnode points at, or nil. This is the usual way
--- to read the format string or name passed to a call.
function pcode.stringOf(varnode, limit: number?): string?
	local address = pcode.addressOf(varnode)
	if address == nil then
		return nil
	end
	local memory = require("@ghidra/memory")
	if not memory.contains(address) then
		return nil
	end
	local data = require("@ghidra").dataAt(address)
	if data ~= nil and data.text ~= nil then
		return data.text
	end
	local ok, text = pcall(memory.cstring, address, limit)
	if not ok or text == "" then
		return nil
	end
	-- Anything can be read as a C string, and a function pointer read that way is
	-- noise rather than an answer, so undefined bytes only count as a string when
	-- they all print.
	for index = 1, #text do
		local byte = string.byte(text, index)
		if byte < 0x20 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
			return nil
		end
		if byte > 0x7e then
			return nil
		end
	end
	return text
end

-- --- Slices ----------------------------------------------------------------

local function slice(name: string, varnode)
	if varnode == nil then
		error("a slice needs a varnode", 3)
	end
	local utils = internal.classes["ghidra.app.decompiler.component.DecompilerUtils"]
	return internal.collect(utils[name](varnode))
end

--- The varnodes a value flows into, as a Luau array.
function pcode.forwardSlice(varnode)
	return slice("getForwardSlice", varnode)
end

--- The varnodes a value flows from, as a Luau array.
function pcode.backwardSlice(varnode)
	return slice("getBackwardSlice", varnode)
end

--- The operations a value flows into, as a Luau array.
function pcode.forwardSliceOps(varnode)
	return slice("getForwardSliceToPCodeOps", varnode)
end

--- The operations a value flows from, as a Luau array.
function pcode.backwardSliceOps(varnode)
	return slice("getBackwardSliceToPCodeOps", varnode)
end

return pcode
