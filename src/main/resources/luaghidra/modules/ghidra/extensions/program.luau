-- The Program itself.

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.listing.Program", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		imageBase = property(function(self)
			return self:getImageBase()
		end),
		minAddress = property(function(self)
			return self:getMinAddress()
		end),
		maxAddress = property(function(self)
			return self:getMaxAddress()
		end),
		languageId = property(function(self)
			return tostring(self:getLanguageID())
		end),
		processor = property(function(self)
			return tostring(self:getLanguage():getProcessor())
		end),
		bigEndian = property(function(self)
			return self:getLanguage():isBigEndian()
		end),
		pointerSize = property(function(self)
			return self:getDefaultPointerSize()
		end),
		compilerName = property(function(self)
			return self:getCompiler()
		end),
		executablePath = property(function(self)
			return self:getExecutablePath()
		end),
		executableFormat = property(function(self)
			return self:getExecutableFormat()
		end),
		executableMd5 = property(function(self)
			return self:getExecutableMD5()
		end),
		executableSha256 = property(function(self)
			return self:getExecutableSHA256()
		end),
		listing = property(function(self)
			return self:getListing()
		end),
		memory = property(function(self)
			return self:getMemory()
		end),
		symbolTable = property(function(self)
			return self:getSymbolTable()
		end),
		functionManager = property(function(self)
			return self:getFunctionManager()
		end),
		dataTypeManager = property(function(self)
			return self:getDataTypeManager()
		end),
		referenceManager = property(function(self)
			return self:getReferenceManager()
		end),
		addressFactory = property(function(self)
			return self:getAddressFactory()
		end),
		defaultSpace = property(function(self)
			return self:getAddressFactory():getDefaultAddressSpace()
		end),
		bookmarkManager = property(function(self)
			return self:getBookmarkManager()
		end),
		globalNamespace = property(function(self)
			return self:getGlobalNamespace()
		end),
		functionCount = property(function(self)
			return self:getFunctionManager():getFunctionCount()
		end),
		symbolCount = property(function(self)
			return self:getSymbolTable():getNumSymbols()
		end),
		changed = property(function(self)
			return self:isChanged()
		end),
	},
	methods = {
		--- Iterates every function in address order.
		functions = function(self, forward: boolean?)
			return internal.iterate(self:getFunctionManager():getFunctions(forward ~= false))
		end,

		--- Runs `body` inside a database transaction, committing on success and
		--- rolling back if it raises. Returns whatever `body` returns.
		transaction = function(self, name: string, body: () -> any): any
			local id = self:startTransaction(name)
			local ok, result = pcall(body)
			self:endTransaction(id, ok)
			if not ok then
				error(result, 0)
			end
			return result
		end,
	},
})

return true
