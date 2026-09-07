-- Address sets, ranges, and set arithmetic.
local t = require("@test")
local ghidra = require("@ghidra")
local addresses = require("@ghidra/addresses")

local main = ghidra.functionAt(0x401000)
local helper = ghidra.functionAt(0x401100)

-- Building sets from every accepted shape.
local set = addresses.set(main.body, helper.body, 0x401300, { 0x401400, 0x40140f })
t.assertEqual(set.size, main.size + helper.size + 1 + 16, "set() unions every piece")
t.assertEqual(set.rangeCount, 4, "and keeps them as separate ranges")
t.assertTrue(set:contains(ghidra.address(0x401300)), "the single address is in the set")

-- Ranges.
local ranges = ghidra.collect(set:ranges())
t.assertEqual(#ranges, 4, "set:ranges()")
t.assertEqual(ranges[1].minAddress.offset, 0x401000, "range.minAddress")
t.assertEqual(ranges[1].length, main.size, "range.length")

local range = addresses.range(0x401000, 0x40100f)
t.assertEqual(range.length, 16, "addresses.range")

-- Individual addresses.
local walked = 0
for _ in addresses.each(main.body) do
	walked += 1
end
t.assertEqual(walked, main.size, "addresses.each walks every byte")

-- Set arithmetic. The Java methods work directly on the result.
t.assertEqual(addresses.union(main.body, helper.body).size, main.size + helper.size, "union")
t.assertEqual(addresses.intersect(set, main.body).size, main.size, "intersect")
t.assertEqual(addresses.subtract(set, main.body).size, set.size - main.size, "subtract")
t.assertEqual(main.body:union(helper.body).size, main.size + helper.size, "the Java union too")
t.assertEqual(addresses.empty().size, 0, "empty")
t.assertTrue(addresses.empty():isEmpty(), "and it reports itself empty")

-- Address spaces.
t.assertEqual(addresses.space():getName(), "ram", "the default address space")
t.assertEqual(addresses.of("00401000").offset, 0x401000, "addresses.of")

-- Addresses compare by value and by order, which is what makes them usable as
-- loop bounds and table keys.
local ghidra2 = require("@ghidra")
t.assertTrue(ghidra2.address(0x401000) == ghidra2.address(0x401000), "equal addresses")
t.assertTrue(ghidra2.address(0x401000) ~= ghidra2.address(0x401004), "unequal addresses")
t.assertTrue(ghidra2.address(0x401000) < ghidra2.address(0x401004), "addresses order")
t.assertTrue(ghidra2.address(0x401004) >= ghidra2.address(0x401004), "and compare with >=")
t.assertTrue(main.entry == ghidra2.address(0x401000), "a function entry equals the address")
t.assertTrue(main.body:contains(main.entry), "and the body contains it")

t.finish("addresses")
