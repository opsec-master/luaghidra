-- Address spaces, including overlays.
local t = require("@test")
local ghidra = require("@ghidra")
local addresses = require("@ghidra/addresses")

-- The default space.
local ram = addresses.space()
t.assertEqual(ram.name, "ram", "the default space")
t.assertEqual(ram.bits, 64, "space.bits")
t.assertEqual(ram.pointerSize, 8, "space.pointerSize")
t.assertEqual(ram.unitSize, 1, "space.unitSize")
t.assertTrue(ram.isMemory, "space.isMemory")
t.assertTrue(ram.isLoaded, "space.isLoaded")
t.assertTrue(not ram.isOverlay, "space.isOverlay")
t.assertTrue(not ram.isRegister, "space.isRegister")
t.assertEqual(ram.minAddress.offset, 0, "space.minAddress")
t.assertEqual(ram.overlayedSpace, nil, "a physical space overlays nothing")
t.assertEqual(ram.physicalSpace.name, "ram", "space.physicalSpace")
t.assertEqual(ram:range().minAddress.offset, 0, "space:range()")

-- Looking a space up by name, and failing helpfully.
t.assertEqual(addresses.space("ram").name, "ram", "addresses.space by name")
local ok, err = pcall(function()
	return addresses.space("nosuchspace")
end)
t.assertTrue(not ok, "an unknown space name raises")
t.assertTrue(string.find(tostring(err), "ram") ~= nil, "and the error lists the real spaces")

-- Addresses know their space.
local addr = ghidra.address(0x401000)
t.assertEqual(addr.space.name, "ram", "address.space is the space object")
t.assertTrue(addr.isMemory, "address.isMemory")
t.assertTrue(addr.isLoaded, "address.isLoaded")
t.assertTrue(not addr.isRegister, "address.isRegister")
t.assertTrue(not addr.isConstant, "address.isConstant")
t.assertEqual(addr.unsignedOffset, 0x401000, "address.unsignedOffset")

-- Listing spaces.
local names = {}
for _, space in addresses.spaces() do
	table.insert(names, space.name)
end
table.sort(names)
t.assertTrue(table.find(names, "ram") ~= nil, "addresses.spaces includes ram")
t.assertTrue(table.find(names, "OVL") ~= nil, "addresses.spaces includes the overlay")
t.assertTrue(#addresses.physicalSpaces() >= 1, "addresses.physicalSpaces")
t.assertEqual(#ghidra.addressSpaces(), #addresses.spaces(), "ghidra.addressSpaces agrees")

-- Overlays.
local overlays = addresses.overlays()
t.assertEqual(#overlays, 1, "addresses.overlays")
local ovl = overlays[1]
t.assertEqual(ovl.name, "OVL", "the overlay's name")
t.assertTrue(ovl.isOverlay, "overlay.isOverlay")
t.assertEqual(ovl.overlayedSpace.name, "ram", "overlay.overlayedSpace")
t.assertTrue(ovl.definedAddresses.size > 0, "overlay.definedAddresses")
t.assertTrue(ovl.showsName, "an overlay qualifies its addresses with its name")

-- Building an address in a specific space. The same offset is a different
-- address in the overlay than it is in ram.
local inOverlay = ghidra.address(0x401000, "OVL")
t.assertEqual(inOverlay.space.name, "OVL", "ghidra.address with a space name")
t.assertEqual(inOverlay.offset, 0x401000, "and the offset is preserved")
t.assertTrue(tostring(inOverlay) ~= tostring(addr), "the two addresses differ")
t.assertTrue(string.find(tostring(inOverlay), "OVL") ~= nil, "the overlay address shows its space")

t.assertEqual(ghidra.address(0x401000, ovl).space.name, "OVL", "a space object works too")
t.assertEqual(addresses.of(0x401000, "OVL").space.name, "OVL", "addresses.of takes a space")
t.assertEqual(ovl:address(0x401004).offset, 0x401004, "space:address()")
t.assertEqual(addr:inSpace("OVL").space.name, "OVL", "address:inSpace()")

-- The program agrees.
local program = ghidra.program()
t.assertEqual(program.defaultSpace.name, "ram", "program.defaultSpace")
t.assertTrue(program.addressFactory ~= nil, "program.addressFactory")
t.assertTrue(addresses.hasMultipleSpaces(), "the overlay means multiple memory spaces")

-- The processor's internal spaces, which P-code works in.
t.assertTrue(addresses.constantSpace().isConstant, "addresses.constantSpace")
t.assertTrue(addresses.registerSpace().isRegister, "addresses.registerSpace")
t.assertTrue(addresses.uniqueSpace().isUnique, "addresses.uniqueSpace")
t.assertTrue(addresses.stackSpace().isStack, "addresses.stackSpace")

t.finish("address spaces")
