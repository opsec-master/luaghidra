-- Function details: signatures, parameters, locals, tags, and thunks.
local t = require("@test")
local ghidra = require("@ghidra")

local main = ghidra.functionAt(0x401000)
local helper = ghidra.functionAt(0x401100)

t.assertEqual(main.qualifiedName, "main", "function.qualifiedName")
t.assertEqual(main.namespace.name, "Global", "function.namespace")
t.assertEqual(main.callingConvention, "unknown", "function.callingConvention")
t.assertTrue(main.returnType ~= nil, "function.returnType")
t.assertTrue(not main.inline, "function.inline")
t.assertTrue(not main.noReturn, "function.noReturn")
t.assertEqual(main.thunkedFunction, nil, "function.thunkedFunction")
t.assertEqual(#main.tags, 0, "function.tags starts empty")
t.assertTrue(main.stackFrame ~= nil, "function.stackFrame")

-- Applying a C prototype rewrites the return type and parameters.
ghidra.transaction("signature", function()
	main:setSignature("int main(int argc, char **argv)")
end)
t.assertEqual(main.returnType:getName(), "int", "setSignature set the return type")
t.assertEqual(#main.parameters, 2, "setSignature set the parameters")
t.assertEqual(main.parameters[1].name, "argc", "parameter.name")
t.assertEqual(main.parameters[1].typeName, "int", "parameter.typeName")
t.assertEqual(main.parameters[2].typeName, "char * *", "a pointer parameter")
t.assertTrue(string.find(main.signature, "int main") ~= nil, "function.signature reflects it")

local badSignature = pcall(function()
	ghidra.transaction("bad", function()
		main:setSignature("this is not a prototype")
	end)
end)
t.assertTrue(not badSignature, "an unparseable signature is rejected")

-- Renaming a parameter, and setting its type.
ghidra.transaction("params", function()
	main.parameters[1].name = "count"
	main.parameters[1].dataType = "long"
end)
t.assertEqual(main.parameters[1].name, "count", "parameter rename through the property")
t.assertEqual(main.parameters[1].typeName, "long", "parameter type through the property")

-- Return type through the property.
ghidra.transaction("return", function()
	main.returnType = "void"
end)
t.assertEqual(main.returnType:getName(), "void", "function.returnType is writable")

-- Tags.
ghidra.transaction("tags", function()
	main:addTag("reviewed")
end)
t.assertEqual(main.tags[1], "reviewed", "function.tags")
ghidra.transaction("untag", function()
	main:removeTag("reviewed")
end)
t.assertEqual(#main.tags, 0, "removeTag")

-- Call relationships.
t.assertEqual(#main:callees(), 1, "function:callees()")
t.assertEqual(main:callees()[1].name, "helper", "and it is helper")
t.assertEqual(#helper:callers(), 1, "function:callers()")
t.assertEqual(#ghidra.collect(helper:xrefs()), 1, "function:xrefs()")

-- Locals: the decompiler has not run, so there are none yet, but the property
-- must still answer.
t.assertEqual(#helper.locals, 0, "function.locals")
t.assertTrue(#helper.variables >= 0, "function.variables")

-- Comments on a function.
ghidra.transaction("comment", function()
	main.comment = "the entry point"
end)
t.assertEqual(main.comment, "the entry point", "function.comment is writable")

t.assertEqual(main.external, false, "function.external")

t.finish("functions")
