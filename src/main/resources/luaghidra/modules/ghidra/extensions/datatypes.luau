-- Data types, their managers, and categories.

local internal = require("@ghidra/internal/host")
local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.data.DataType", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		displayName = property(function(self)
			return self:getDisplayName()
		end),
		length = property(function(self)
			return self:getLength()
		end),
		alignment = property(function(self)
			return self:getAlignment()
		end),
		description = property(function(self)
			return self:getDescription()
		end),
		--- The full path, e.g. "/MyCategory/Header".
		path = property(function(self)
			return self:getPathName()
		end),
		category = property(function(self)
			return self:getCategoryPath():getPath()
		end),
		--- The manager this type belongs to, which is not necessarily the
		--- program's; see @ghidra/datatypes for moving one across.
		manager = property(function(self)
			return self:getDataTypeManager()
		end),
	},
})

java.extend("ghidra.program.model.data.Composite", {
	properties = {
		componentCount = property(function(self)
			return self:getNumComponents()
		end),
	},
	methods = {
		--- The structure's or union's fields, as a Luau array.
		fields = function(self)
			return internal.collect(self:getComponents())
		end,
	},
})

java.extend("ghidra.program.model.data.DataTypeComponent", {
	properties = {
		fieldName = property(function(self)
			return self:getFieldName()
		end),
		offset = property(function(self)
			return self:getOffset()
		end),
		length = property(function(self)
			return self:getLength()
		end),
		dataType = property(function(self)
			return self:getDataType()
		end),
		typeName = property(function(self)
			return self:getDataType():getName()
		end),
		comment = property(function(self)
			return self:getComment()
		end),
	},
})

java.extend("ghidra.program.model.data.DataTypeManager", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		--- Where the types come from: BUILT_IN, FILE, PROJECT, PROGRAM, or
		--- TEMPORARY.
		kind = property(function(self)
			return tostring(self:getType())
		end),
		typeCount = property(function(self)
			return self:getDataTypeCount(false)
		end),
		categoryCount = property(function(self)
			return self:getCategoryCount()
		end),
		rootCategory = property(function(self)
			return self:getRootCategory()
		end),
	},
	methods = {
		--- Iterates every data type in this manager.
		types = function(self)
			return internal.iterate(self:getAllDataTypes())
		end,

		--- The first type with this name in this manager, or nil.
		find = function(self, name: string)
			return require("@ghidra/datatypes").find(name, self)
		end,
	},
})

java.extend("ghidra.program.model.data.Category", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		path = property(function(self)
			return self:getCategoryPathName()
		end),
		parent = property(function(self)
			return self:getParent()
		end),
		manager = property(function(self)
			return self:getDataTypeManager()
		end),
	},
	methods = {
		--- The types declared directly in this category, as a Luau array.
		types = function(self)
			return internal.collect(self:getDataTypes())
		end,

		--- The immediate child categories, as a Luau array.
		children = function(self)
			return internal.collect(self:getCategories())
		end,
	},
})

return true
