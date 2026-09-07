-- P-code: operations, varnodes, and the decompiler's view of a function.

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.pcode.PcodeOp", {
	properties = {
		mnemonic = property(function(self)
			return self:getMnemonic()
		end),
		opcode = property(function(self)
			return self:getOpcode()
		end),
		output = property(function(self)
			return self:getOutput()
		end),
		inputCount = property(function(self)
			return self:getNumInputs()
		end),
		--- The address of the instruction this operation came from.
		address = property(function(self)
			return self:getSeqnum():getTarget()
		end),
		parent = property(function(self)
			return self:getParent()
		end),
	},
	methods = {
		--- The operation's inputs, as a Luau array. Reading past the end is nil
		--- rather than an error, unlike indexing the Java array.
		inputs = function(self)
			local count = self:getNumInputs()
			local out = table.create(count)
			for index = 0, count - 1 do
				out[index + 1] = self:getInput(index)
			end
			return out
		end,

		--- One input by 1-based index, or nil when there are fewer than that.
		input = function(self, index: number)
			if index < 1 or index > self:getNumInputs() then
				return nil
			end
			return self:getInput(index - 1)
		end,
	},
})

java.extend("ghidra.program.model.pcode.Varnode", {
	properties = {
		offset = property(function(self)
			return self:getOffset()
		end),
		size = property(function(self)
			return self:getSize()
		end),
		address = property(function(self)
			return self:getAddress()
		end),
		--- The operation that defined this varnode, or nil for an input.
		def = property(function(self)
			return self:getDef()
		end),
		--- The decompiler's variable this varnode belongs to, or nil.
		high = property(function(self)
			return self:getHigh()
		end),
	},
	methods = {
		--- The operations that read this varnode, as a Luau array.
		descendants = function(self)
			return internal.collect(self:getDescendants())
		end,
	},
})

java.extend("ghidra.program.model.pcode.HighVariable", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		dataType = property(function(self)
			return self:getDataType()
		end),
		size = property(function(self)
			return self:getSize()
		end),
		--- The varnode that stands for this variable in slices and p-code.
		representative = property(function(self)
			return self:getRepresentative()
		end),
	},
	methods = {
		--- Every varnode this variable is stored in, as a Luau array.
		instances = function(self)
			return internal.collect(self:getInstances())
		end,
	},
})

java.extend("ghidra.program.model.pcode.HighSymbol", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		dataType = property(function(self)
			return self:getDataType()
		end),
		size = property(function(self)
			return self:getSize()
		end),
		storage = property(function(self)
			return self:getStorage()
		end),
		variable = property(function(self)
			return self:getHighVariable()
		end),
	},
})

java.extend("ghidra.program.model.block.CodeBlock", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		--- Where control enters the block.
		start = property(function(self)
			return self:getFirstStartAddress()
		end),
		flow = property(function(self)
			return tostring(self:getFlowType())
		end),
	},
	methods = {
		--- Iterates the blocks control can reach from this one.
		successors = function(self)
			return require("@ghidra/blocks").successors(self)
		end,

		--- Iterates the blocks that can reach this one.
		predecessors = function(self)
			return require("@ghidra/blocks").predecessors(self)
		end,
	},
})

java.extend("ghidra.program.model.block.CodeBlockReference", {
	properties = {
		from = property(function(self)
			return self:getReferent()
		end),
		to = property(function(self)
			return self:getReference()
		end),
		sourceBlock = property(function(self)
			return self:getSourceBlock()
		end),
		destinationBlock = property(function(self)
			return self:getDestinationBlock()
		end),
		flow = property(function(self)
			return tostring(self:getFlowType())
		end),
	},
})

return true
