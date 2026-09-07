-- Symbols, namespaces, references, and bookmarks.

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.symbol.Symbol", {
	properties = {
		name = property(function(self)
			return self:getName()
		end, function(self, value: string)
			self:setName(value, support.sourceType())
		end),
		qualifiedName = property(function(self)
			return self:getName(true)
		end),
		address = property(function(self)
			return self:getAddress()
		end),
		namespace = property(function(self)
			return self:getParentNamespace()
		end),
		kind = property(function(self)
			return tostring(self:getSymbolType())
		end),
		source = property(function(self)
			return tostring(self:getSource())
		end),
		primary = property(function(self)
			return self:isPrimary()
		end),
		external = property(function(self)
			return self:isExternal()
		end),
		referenceCount = property(function(self)
			return self:getReferenceCount()
		end),
	},
	methods = {
		rename = function(self, name: string, source: string?)
			self:setName(name, support.sourceType(source))
		end,

		--- Moves the symbol into a namespace. Must run inside a transaction.
		moveTo = function(self, namespace, source: string?)
			self:setNamespace(namespace)
			if source ~= nil then
				self:setName(self:getName(), support.sourceType(source))
			end
		end,

		--- Iterates references pointing at this symbol.
		xrefs = function(self)
			return internal.iterate(self:getReferences(internal.context():getMonitor()))
		end,
	},
})

java.extend("ghidra.program.model.symbol.Namespace", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		path = property(function(self)
			return self:getName(true)
		end),
		parent = property(function(self)
			return self:getParentNamespace()
		end),
	},
	methods = {
		--- Iterates the symbols declared in this namespace.
		symbols = function(self)
			return internal.iterate(
				internal.program():getSymbolTable():getSymbols(self)
			)
		end,
	},
})

java.extend("ghidra.program.model.symbol.Reference", {
	properties = {
		from = property(function(self)
			return self:getFromAddress()
		end),
		to = property(function(self)
			return self:getToAddress()
		end),
		kind = property(function(self)
			return tostring(self:getReferenceType())
		end),
		refType = property(function(self)
			return self:getReferenceType()
		end),
		operand = property(function(self)
			local index = self:getOperandIndex()
			return if index >= 0 then index + 1 else nil
		end),
		source = property(function(self)
			return tostring(self:getSource())
		end),
		isCall = property(function(self)
			return self:getReferenceType():isCall()
		end),
		isJump = property(function(self)
			return self:getReferenceType():isJump()
		end),
		isRead = property(function(self)
			return self:getReferenceType():isRead()
		end),
		isWrite = property(function(self)
			return self:getReferenceType():isWrite()
		end),
		--- True for any data reference, including the PARAM references Ghidra
		--- makes for a string or constant passed to a call.
		isData = property(function(self)
			return self:getReferenceType():isData()
		end),
		isFlow = property(function(self)
			return self:getReferenceType():isFlow()
		end),
		isIndirect = property(function(self)
			return self:getReferenceType():isIndirect()
		end),
	},
	methods = {
		--- The function containing the reference's source address, or nil.
		fromFunction = function(self)
			return internal.program():getFunctionManager()
				:getFunctionContaining(self:getFromAddress())
		end,

		--- The function the reference points at, or nil.
		toFunction = function(self)
			return internal.program():getFunctionManager():getFunctionAt(self:getToAddress())
		end,
	},
})

java.extend("ghidra.program.model.listing.Bookmark", {
	properties = {
		address = property(function(self)
			return self:getAddress()
		end),
		kind = property(function(self)
			return self:getTypeString()
		end),
		category = property(function(self)
			return self:getCategory()
		end),
		comment = property(function(self)
			return self:getComment()
		end),
	},
})

return true
