-- Memory blocks.

local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.mem.MemoryBlock", {
	properties = {
		name = property(function(self)
			return self:getName()
		end, function(self, value: string)
			self:setName(value)
		end),
		start = property(function(self)
			return self:getStart()
		end),
		endAddress = property(function(self)
			return self:getEnd()
		end),
		size = property(function(self)
			return self:getSize()
		end),
		readable = property(function(self)
			return self:isRead()
		end, function(self, value: boolean)
			self:setRead(value)
		end),
		writable = property(function(self)
			return self:isWrite()
		end, function(self, value: boolean)
			self:setWrite(value)
		end),
		executable = property(function(self)
			return self:isExecute()
		end, function(self, value: boolean)
			self:setExecute(value)
		end),
		initialized = property(function(self)
			return self:isInitialized()
		end),
		comment = property(function(self)
			return self:getComment()
		end, function(self, value: string?)
			self:setComment(value)
		end),
	},
	methods = {
		--- The block's extent as an AddressSet.
		addressSet = function(self)
			local AddressSet = require("@ghidra/internal/host").classes["ghidra.program.model.address.AddressSet"]
			return AddressSet(self:getStart(), self:getEnd())
		end,
	},
})

return true
