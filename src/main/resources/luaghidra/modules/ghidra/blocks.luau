-- Basic blocks and control flow.
--
--     local blocks = require("@ghidra/blocks")
--
--     for block in blocks.of(func) do
--         print(block.name, block.start, block.size)
--         for successor in block:successors() do
--             print("  ->", successor.start)
--         end
--     end
--
-- Blocks are Ghidra `CodeBlock`s, which are address sets, so the address-set
-- properties and methods apply to them too.

local internal = require("@ghidra/internal/host")

local blocks = {}

local model = nil
local modelProgram = nil

local function blockModel()
	local program = internal.program()
	if model == nil or modelProgram ~= program then
		model = internal.classes["ghidra.program.model.block.BasicBlockModel"](program)
		modelProgram = program
	end
	return model
end

local function monitor()
	return internal.context():getMonitor()
end

--- Iterates the basic blocks of a function, an address set, or the whole
--- program when given nothing.
function blocks.of(target)
	if target == nil then
		return internal.iterate(blockModel():getCodeBlocks(monitor()))
	end
	local set = if internal.hasMethod(target, "getBody") then target:getBody() else target
	return internal.iterate(blockModel():getCodeBlocksContaining(set, monitor()))
end

--- The basic block starting at an address, or nil.
function blocks.at(address)
	return blockModel():getCodeBlockAt(internal.context():toAddress(address), monitor())
end

--- Every basic block covering an address, as a Luau array.
function blocks.containing(address)
	return internal.collect(
		blockModel():getCodeBlocksContaining(internal.context():toAddress(address), monitor())
	)
end

--- Iterates the blocks control can reach from this one.
function blocks.successors(block)
	local step = internal.iterate(block:getDestinations(monitor()))
	return function()
		local reference = step()
		return if reference ~= nil then reference:getDestinationBlock() else nil
	end
end

--- Iterates the blocks that can reach this one.
function blocks.predecessors(block)
	local step = internal.iterate(block:getSources(monitor()))
	return function()
		local reference = step()
		return if reference ~= nil then reference:getSourceBlock() else nil
	end
end

--- Iterates the outgoing flow references of a block, which carry the flow type
--- alongside the destination.
function blocks.flowsOut(block)
	return internal.iterate(block:getDestinations(monitor()))
end

--- Iterates the incoming flow references of a block.
function blocks.flowsIn(block)
	return internal.iterate(block:getSources(monitor()))
end

--- Releases the cached block model. It is rebuilt on the next call.
function blocks.reset()
	model = nil
	modelProgram = nil
end

return blocks
