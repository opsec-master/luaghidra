-- Addresses, address spaces, address ranges, and address sets.

local support = require("@ghidra/internal/ext")
local property = support.property

java.extend("ghidra.program.model.address.Address", {
	properties = {
		offset = property(function(self)
			return self:getOffset()
		end),
		unsignedOffset = property(function(self)
			return self:getUnsignedOffset()
		end),
		--- The AddressSpace this address lives in. Its name is `.space.name`.
		space = property(function(self)
			return self:getAddressSpace()
		end),
		isMemory = property(function(self)
			return self:isMemoryAddress()
		end),
		isLoaded = property(function(self)
			return self:isLoadedMemoryAddress()
		end),
		isRegister = property(function(self)
			return self:isRegisterAddress()
		end),
		isStack = property(function(self)
			return self:isStackAddress()
		end),
		isConstant = property(function(self)
			return self:isConstantAddress()
		end),
		isUnique = property(function(self)
			return self:isUniqueAddress()
		end),
		isExternal = property(function(self)
			return self:isExternalAddress()
		end),
	},
	methods = {
		--- Formats the address as it appears in the listing, e.g. "00401000",
		--- or "OVL1::00001000" in a space that shows its name.
		format = function(self): string
			return tostring(self)
		end,

		--- The same offset in another space, given an AddressSpace or its name.
		inSpace = function(self, space)
			return require("@ghidra/internal/host").context()
				:toAddressSpace(space):getAddress(self:getOffset())
		end,
	},
})

-- --- Address spaces ------------------------------------------------------

java.extend("ghidra.program.model.address.AddressSpace", {
	properties = {
		name = property(function(self)
			return self:getName()
		end),
		--- The width of an address in this space, in bits.
		bits = property(function(self)
			return self:getSize()
		end),
		pointerSize = property(function(self)
			return self:getPointerSize()
		end),
		--- Bytes per addressable unit: 1 on byte-addressed machines, more on
		--- word-addressed ones such as some DSPs.
		unitSize = property(function(self)
			return self:getAddressableUnitSize()
		end),
		spaceId = property(function(self)
			return self:getSpaceID()
		end),
		minAddress = property(function(self)
			return self:getMinAddress()
		end),
		maxAddress = property(function(self)
			return self:getMaxAddress()
		end),
		--- For an overlay space, the space it overlays; nil otherwise.
		overlayedSpace = property(function(self)
			return if self:isOverlaySpace() then self:getOverlayedSpace() else nil
		end),
		physicalSpace = property(function(self)
			return self:getPhysicalSpace()
		end),
		isOverlay = property(function(self)
			return self:isOverlaySpace()
		end),
		isMemory = property(function(self)
			return self:isMemorySpace()
		end),
		isLoaded = property(function(self)
			return self:isLoadedMemorySpace()
		end),
		isRegister = property(function(self)
			return self:isRegisterSpace()
		end),
		isStack = property(function(self)
			return self:isStackSpace()
		end),
		isConstant = property(function(self)
			return self:isConstantSpace()
		end),
		isUnique = property(function(self)
			return self:isUniqueSpace()
		end),
		isExternal = property(function(self)
			return self:isExternalSpace()
		end),
		isHash = property(function(self)
			return self:isHashSpace()
		end),
		isVariable = property(function(self)
			return self:isVariableSpace()
		end),
		--- Whether Ghidra qualifies addresses in this space with its name.
		showsName = property(function(self)
			return self:showSpaceName()
		end),
	},
	methods = {
		--- An address at this offset within the space.
		address = function(self, offset: number)
			return self:getAddress(offset)
		end,

		--- The whole space as an AddressSet, from its minimum to its maximum.
		range = function(self)
			local AddressSet =
				require("@ghidra/internal/host").classes["ghidra.program.model.address.AddressSet"]
			return AddressSet(self:getMinAddress(), self:getMaxAddress())
		end,
	},
})

java.extend("ghidra.program.model.address.OverlayAddressSpace", {
	properties = {
		--- The addresses this overlay actually defines, which is usually a
		--- smaller set than the space's full min-to-max range.
		definedAddresses = property(function(self)
			return self:getOverlayAddressSet()
		end),
	},
})

-- --- Ranges and sets -----------------------------------------------------

java.extend("ghidra.program.model.address.AddressRange", {
	properties = {
		minAddress = property(function(self)
			return self:getMinAddress()
		end),
		maxAddress = property(function(self)
			return self:getMaxAddress()
		end),
		length = property(function(self)
			return self:getLength()
		end),
		space = property(function(self)
			return self:getAddressSpace()
		end),
	},
})

java.extend("ghidra.program.model.address.AddressSetView", {
	properties = {
		size = property(function(self)
			return self:getNumAddresses()
		end),
		minAddress = property(function(self)
			return self:getMinAddress()
		end),
		maxAddress = property(function(self)
			return self:getMaxAddress()
		end),
		rangeCount = property(function(self)
			return self:getNumAddressRanges()
		end),
	},
	methods = {
		--- Iterates the set's address ranges.
		ranges = function(self)
			return require("@ghidra/internal/host").iterate(self:getAddressRanges())
		end,

		--- Iterates every address in the set, one at a time.
		addresses = function(self, forward: boolean?)
			return require("@ghidra/internal/host").iterate(self:getAddresses(forward ~= false))
		end,
	},
})

return true
