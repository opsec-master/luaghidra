-- Addresses, address sets, and address spaces.
--
--     local addresses = require("@ghidra/addresses")
--
--     local body = addresses.set(func.body, otherFunc.body)
--     for range in body:ranges() do
--         print(range.minAddress, range.length)
--     end
--
-- Address sets returned here are Ghidra `AddressSet`s, so their Java methods —
-- `union`, `intersect`, `subtract`, `xor`, `contains` — work directly.
--
-- Address spaces live here too: `addresses.spaces()` lists them, and
-- `addresses.of(offset, "OVL1")` builds an address in a particular one.

local internal = require("@ghidra/internal/host")

local addresses = {}

local function addressSetClass()
	return internal.classes["ghidra.program.model.address.AddressSet"]
end

local function factory()
	return internal.program():getAddressFactory()
end

-- --- Addresses -----------------------------------------------------------

--- Coerces a string, number, or Address into an Address. A number is an offset
--- in `space`, or in the program's default space when that is omitted.
function addresses.of(value, space)
	return internal.context():toAddress(value, space)
end

--- An AddressRange spanning `first` through `last`, inclusive.
function addresses.range(first, last)
	local Range = internal.classes["ghidra.program.model.address.AddressRangeImpl"]
	return Range(addresses.of(first), addresses.of(last))
end

-- --- Address sets --------------------------------------------------------

--- Builds an AddressSet from any mix of addresses, ranges, address sets, and
--- `{ first, last }` pairs.
---
---     addresses.set(0x401000, func.body, { 0x402000, 0x402fff })
function addresses.set(...)
	local result = addressSetClass()()
	for _, piece in { ... } do
		if piece == nil then
			continue
		end
		if typeof(piece) == "table" then
			result:addRange(addresses.of(piece[1]), addresses.of(piece[2]))
		elseif typeof(piece) == "string" or typeof(piece) == "number" then
			result:add(addresses.of(piece))
		else
			result:add(piece)
		end
	end
	return result
end

--- An empty AddressSet.
function addresses.empty()
	return addressSetClass()()
end

--- The union of every argument.
function addresses.union(...)
	return addresses.set(...)
end

--- The intersection of every argument.
function addresses.intersect(first, ...)
	local result = addresses.set(first)
	for _, other in { ... } do
		result = result:intersect(addresses.set(other))
	end
	return result
end

--- `first` with everything in the remaining arguments removed.
function addresses.subtract(first, ...)
	local result = addresses.set(first)
	for _, other in { ... } do
		result = result:subtract(addresses.set(other))
	end
	return result
end

--- Iterates the ranges of an address set.
function addresses.ranges(set)
	return internal.iterate(set:getAddressRanges())
end

--- Iterates every address in a set, one at a time.
function addresses.each(set, forward: boolean?)
	return internal.iterate(set:getAddresses(forward ~= false))
end

--- The addresses the program's memory actually covers.
function addresses.program()
	return internal.program():getMemory()
end

-- --- Address spaces ------------------------------------------------------

--- An address space by name, or the program's default space when no name is
--- given. Raises when the program has no space of that name, listing the ones
--- it does have.
function addresses.space(name: string?)
	if name == nil then
		return factory():getDefaultAddressSpace()
	end
	return internal.context():toAddressSpace(name)
end

--- Every address space the program defines, including overlays, as a Luau
--- array.
function addresses.spaces()
	return internal.collect(factory():getAllAddressSpaces())
end

--- The program's physical memory spaces, without overlays or the processor's
--- internal spaces.
function addresses.physicalSpaces()
	return internal.collect(factory():getPhysicalSpaces())
end

--- The program's overlay spaces, as a Luau array.
function addresses.overlays()
	local out = {}
	local count = 0
	for _, space in addresses.spaces() do
		if space:isOverlaySpace() then
			count += 1
			out[count] = space
		end
	end
	return out
end

--- Whether the program has more than one memory space, which is what makes
--- naming a space in `addresses.of` necessary rather than optional.
function addresses.hasMultipleSpaces(): boolean
	return factory():hasMultipleMemorySpaces()
end

--- The processor's constant space, used by P-code for literal values.
function addresses.constantSpace()
	return factory():getConstantSpace()
end

--- The processor's register space.
function addresses.registerSpace()
	return factory():getRegisterSpace()
end

--- The processor's stack space.
function addresses.stackSpace()
	return factory():getStackSpace()
end

--- The processor's unique space, used by P-code for temporaries.
function addresses.uniqueSpace()
	return factory():getUniqueSpace()
end

--- The program's AddressFactory, for anything this module does not wrap.
function addresses.factory()
	return factory()
end

return addresses
