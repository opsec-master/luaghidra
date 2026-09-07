-- Functions, their variables, and their signatures.

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.listing.Function", {
	properties = {
		name = property(function(self)
			return self:getName()
		end, function(self, value: string)
			self:setName(value, support.sourceType())
		end),
		qualifiedName = property(function(self)
			return self:getName(true)
		end),
		entry = property(function(self)
			return self:getEntryPoint()
		end),
		body = property(function(self)
			return self:getBody()
		end),
		size = property(function(self)
			return self:getBody():getNumAddresses()
		end),
		signature = property(function(self)
			return self:getPrototypeString(true, false)
		end),
		program = property(function(self)
			return self:getProgram()
		end),
		namespace = property(function(self)
			return self:getParentNamespace()
		end),
		comment = property(function(self)
			return self:getComment()
		end, function(self, value: string?)
			self:setComment(value)
		end),
		returnType = property(function(self)
			return self:getReturnType()
		end, function(self, value)
			self:setReturnType(support.dataType(value), support.sourceType())
		end),
		callingConvention = property(function(self)
			return self:getCallingConventionName()
		end, function(self, value: string)
			self:setCallingConvention(value)
		end),
		parameters = property(function(self)
			return internal.collect(self:getParameters())
		end),
		locals = property(function(self)
			return internal.collect(self:getLocalVariables())
		end),
		variables = property(function(self)
			return internal.collect(self:getAllVariables())
		end),
		thunkedFunction = property(function(self)
			return self:getThunkedFunction(true)
		end),
		tags = property(function(self)
			local out = {}
			local count = 0
			for tag in internal.iterate(self:getTags()) do
				count += 1
				out[count] = tag:getName()
			end
			return out
		end),
		stackFrame = property(function(self)
			return self:getStackFrame()
		end),
		inline = property(function(self)
			return self:isInline()
		end, function(self, value: boolean)
			self:setInline(value)
		end),
		noReturn = property(function(self)
			return self:hasNoReturn()
		end, function(self, value: boolean)
			self:setNoReturn(value)
		end),
		--- True for a function that lives in another binary, matching
		--- `symbol.external`.
		external = property(function(self)
			return self:isExternal()
		end),
	},
	methods = {
		--- Renames the function. Defaults to the USER_DEFINED source type.
		rename = function(self, name: string, source: string?)
			self:setName(name, support.sourceType(source))
		end,

		--- Applies a C prototype, replacing the return type and parameters.
		---
		---     func:setSignature("int main(int argc, char **argv)")
		---
		--- Must run inside a transaction.
		setSignature = function(self, prototype: string, source: string?)
			local program = self:getProgram()
			local Parser = internal.classes["ghidra.app.util.parser.FunctionSignatureParser"]
			local parser = Parser(program:getDataTypeManager(), nil)

			local ok, definition = pcall(function()
				return parser:parse(self:getSignature(), prototype)
			end)
			if not ok or definition == nil then
				error(`could not parse the signature '{prototype}': {tostring(definition)}`, 2)
			end

			local Apply = internal.classes["ghidra.app.cmd.function.ApplyFunctionSignatureCmd"]
			local command = Apply(self:getEntryPoint(), definition, support.sourceType(source))
			if not command:applyTo(program, internal.context():getMonitor()) then
				error(`could not apply the signature: {command:getStatusMsg()}`, 2)
			end
		end,

		--- Iterates the instructions in the function body.
		instructions = function(self)
			return internal.iterate(
				self:getProgram():getListing():getInstructions(self:getBody(), true)
			)
		end,

		--- Iterates the defined data inside the function body.
		data = function(self)
			return internal.iterate(
				self:getProgram():getListing():getDefinedData(self:getBody(), true)
			)
		end,

		--- The functions this one calls, as a Luau array.
		callees = function(self)
			return internal.collect(self:getCalledFunctions(internal.context():getMonitor()))
		end,

		--- The functions that call this one, as a Luau array.
		callers = function(self)
			return internal.collect(self:getCallingFunctions(internal.context():getMonitor()))
		end,

		--- Iterates references pointing at the function's entry point.
		xrefs = function(self)
			return internal.iterate(
				self:getProgram():getReferenceManager():getReferencesTo(self:getEntryPoint())
			)
		end,

		--- The function's cyclomatic complexity: the number of independent paths
		--- through it, which is the usual first measure of how gnarly it is.
		complexity = function(self): number
			local CyclomaticComplexity =
				internal.classes["ghidra.program.util.CyclomaticComplexity"]
			return CyclomaticComplexity():calculateCyclomaticComplexity(
				self,
				internal.context():getMonitor()
			)
		end,

		--- Iterates the calls this function makes, with the arguments the
		--- decompiler worked out. See @ghidra/pcode for the call shape.
		calls = function(self, options)
			return require("@ghidra/pcode").calls(self, options)
		end,

		--- Iterates the call sites of this function, from its callers' side, so
		--- each one carries its arguments. See @ghidra/pcode.
		callSites = function(self, options)
			return require("@ghidra/pcode").callsTo(self, options)
		end,

		--- Decompiles the function. See @ghidra/decompiler for the result shape.
		decompile = function(self, options)
			return require("@ghidra/decompiler").decompile(self, options)
		end,

		--- The decompiler's HighFunction, or nil when decompilation failed.
		highFunction = function(self, options)
			local result = require("@ghidra/decompiler").decompile(self, options)
			return if result.ok then result.highFunction else nil
		end,

		--- The function's basic blocks, as a Luau array.
		blocks = function(self)
			return require("@ghidra/blocks").of(self)
		end,
	},
})

java.extend("ghidra.program.model.listing.Variable", {
	properties = {
		name = property(function(self)
			return self:getName()
		end, function(self, value: string)
			self:setName(value, support.sourceType())
		end),
		dataType = property(function(self)
			return self:getDataType()
		end, function(self, value)
			self:setDataType(support.dataType(value), support.sourceType())
		end),
		typeName = property(function(self)
			return self:getDataType():getName()
		end),
		length = property(function(self)
			return self:getLength()
		end),
		comment = property(function(self)
			return self:getComment()
		end, function(self, value: string?)
			self:setComment(value)
		end),
		storage = property(function(self)
			return tostring(self:getVariableStorage())
		end),
		onStack = property(function(self)
			return self:isStackVariable()
		end),
		stackOffset = property(function(self)
			return if self:isStackVariable() then self:getStackOffset() else nil
		end),
		inRegister = property(function(self)
			return self:isRegisterVariable()
		end),
		register = property(function(self)
			return self:getRegister()
		end),
	},
	methods = {
		rename = function(self, name: string, source: string?)
			self:setName(name, support.sourceType(source))
		end,
	},
})

return true
