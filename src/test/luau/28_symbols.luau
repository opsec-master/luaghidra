-- Symbols, labels, namespaces, and entry points.
local t = require("@test")
local ghidra = require("@ghidra")
local symbols = require("@ghidra/symbols")

local main = symbols.at(0x401000)
t.assertEqual(main.name, "main", "symbols.at")
t.assertEqual(main.qualifiedName, "main", "symbol.qualifiedName in the global namespace")
t.assertEqual(main.kind, "Function", "symbol.kind")
t.assertEqual(main.source, "USER_DEFINED", "symbol.source")
t.assertTrue(main.primary, "symbol.primary")
t.assertTrue(not main.external, "symbol.external")

t.assertEqual(#ghidra.collect(symbols.named("helper")), 1, "symbols.named")
t.assertEqual(#symbols.allAt(0x401200), 1, "symbols.allAt")
t.assertEqual(symbols.at(0x401200).name, "a_label", "the label is where we left it")

-- Namespaces.
local created = ghidra.transaction("namespaces", function()
	return symbols.namespace("MyLib/Internals")
end)
t.assertEqual(created.name, "Internals", "namespace.name")
t.assertEqual(created.path, "MyLib::Internals", "namespace.path")
t.assertEqual(created.parent.name, "MyLib", "namespace.parent")
t.assertTrue(symbols.findNamespace("MyLib/Internals") ~= nil, "findNamespace finds it")
t.assertEqual(symbols.findNamespace("MyLib/Nope"), nil, "findNamespace misses cleanly")
t.assertEqual(symbols.global():getName(), "Global", "symbols.global")

-- Requiring the same namespace again returns the existing one.
local again = ghidra.transaction("namespaces again", function()
	return symbols.namespace("MyLib/Internals")
end)
t.assertEqual(again.path, created.path, "namespace() is idempotent")

-- Labels, including into a namespace.
ghidra.transaction("label", function()
	symbols.createLabel(0x401300, "scoped", created)
end)
local scoped = symbols.at(0x401300)
t.assertEqual(scoped.name, "scoped", "createLabel")
t.assertEqual(scoped.qualifiedName, "MyLib::Internals::scoped", "the label landed in the namespace")
t.assertEqual(scoped.namespace.name, "Internals", "symbol.namespace")

local inNamespace = ghidra.collect(created:symbols())
t.assertEqual(#inNamespace, 1, "namespace:symbols()")

ghidra.transaction("unlabel", function()
	t.assertTrue(symbols.remove(scoped), "symbols.remove")
end)
t.assertEqual(symbols.at(0x401300), nil, "the label is gone")

-- Filtering by address set.
local inMain = ghidra.collect(symbols.all({ set = ghidra.functionAt(0x401000).body }))
t.assertEqual(#inMain, 1, "symbols.all restricted to an address set")

-- Entry points: none are set on this scratch program.
t.assertEqual(#ghidra.collect(symbols.entryPoints()), 0, "symbols.entryPoints")
t.assertEqual(#ghidra.collect(ghidra.entryPoints()), 0, "ghidra.entryPoints")

t.finish("symbols")
