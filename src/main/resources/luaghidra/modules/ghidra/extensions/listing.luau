-- Code units: instructions and data.

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")
local property = support.property

local COMMENT_KINDS = { "EOL", "PRE", "POST", "PLATE", "REPEATABLE" }

local function commentType(kind: string)
	return internal.classes["ghidra.program.model.listing.CommentType"][kind]
end

java.extend("ghidra.program.model.listing.CodeUnit", {
	properties = {
		address = property(function(self)
			return self:getMinAddress()
		end),
		endAddress = property(function(self)
			return self:getMaxAddress()
		end),
		length = property(function(self)
			return self:getLength()
		end),
		bytes = property(function(self)
			return self:getBytes()
		end),
		label = property(function(self)
			return self:getLabel()
		end),
		program = property(function(self)
			return self:getProgram()
		end),
	},
	methods = {
		--- Reads one of this code unit's comments. `kind` defaults to "EOL".
		comment = function(self, kind: string?): string?
			return self:getComment(commentType(string.upper(kind or "EOL")))
		end,

		--- Sets one of this code unit's comments. Must run inside a transaction.
		setCommentText = function(self, text: string?, kind: string?)
			self:setComment(commentType(string.upper(kind or "EOL")), text)
		end,

		--- Every comment on this code unit, keyed by kind.
		comments = function(self): { [string]: string }
			local out = {}
			for _, kind in COMMENT_KINDS do
				local text = self:getComment(commentType(kind))
				if text ~= nil then
					out[kind] = text
				end
			end
			return out
		end,

		--- Iterates references originating at this code unit.
		xrefsFrom = function(self)
			return internal.iterate(self:getReferencesFrom())
		end,

		--- Iterates references pointing at this code unit.
		xrefsTo = function(self)
			return internal.iterate(
				self:getProgram():getReferenceManager():getReferencesTo(self:getMinAddress())
			)
		end,
	},
})

java.extend("ghidra.program.model.listing.Instruction", {
	properties = {
		mnemonic = property(function(self)
			return self:getMnemonicString()
		end),
		operandCount = property(function(self)
			return self:getNumOperands()
		end),
		flow = property(function(self)
			return tostring(self:getFlowType())
		end),
		fallThrough = property(function(self)
			return self:getFallThrough()
		end),
		isCall = property(function(self)
			return self:getFlowType():isCall()
		end),
		isJump = property(function(self)
			return self:getFlowType():isJump()
		end),
		isTerminator = property(function(self)
			return self:getFlowType():isTerminal()
		end),
		text = property(function(self)
			return tostring(self)
		end),
	},
	methods = {
		--- The instruction's operands as display strings.
		operands = function(self): { string }
			local out = table.create(self:getNumOperands())
			for index = 0, self:getNumOperands() - 1 do
				out[index + 1] = self:getDefaultOperandRepresentation(index)
			end
			return out
		end,

		--- The scalar (immediate) value of an operand, or nil. Operands are
		--- 1-based here, matching the rest of this API.
		scalar = function(self, operand: number): number?
			local value = self:getScalar(operand - 1)
			return if value ~= nil then value:getValue() else nil
		end,

		--- The register an operand names, or nil.
		registerOf = function(self, operand: number)
			return self:getRegister(operand - 1)
		end,

		--- The addresses this instruction can flow to, as a Luau array.
		flowsTo = function(self)
			return internal.collect(self:getFlows())
		end,

		--- The instruction's raw P-code operations, as a Luau array.
		pcode = function(self)
			return internal.collect(self:getPcode())
		end,
	},
})

java.extend("ghidra.program.model.listing.Data", {
	properties = {
		value = property(function(self)
			return self:getValue()
		end),
		typeName = property(function(self)
			return self:getDataType():getName()
		end),
		dataType = property(function(self)
			return self:getDataType()
		end),
		text = property(function(self)
			return internal.context():stringValue(self)
		end),
		componentCount = property(function(self)
			return self:getNumComponents()
		end),
		parent = property(function(self)
			return self:getParent()
		end),
		fieldName = property(function(self)
			return self:getFieldName()
		end),
	},
	methods = {
		--- The sub-components of a structure or array, as a Luau array.
		components = function(self)
			local count = self:getNumComponents()
			local out = table.create(count)
			for index = 0, count - 1 do
				out[index + 1] = self:getComponent(index)
			end
			return out
		end,
	},
})

return true
