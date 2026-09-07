-- Reading and writing program memory.
--
--     local memory = require("@ghidra/memory")
--     print(memory.u32(0x401000))
--     print(memory.hex(memory.read(0x401000, 16)))
--
-- Multi-byte reads use the program's endianness.

local internal = require("@ghidra/internal/host")

local memory = {}

local function bytes(address, length: number)
	return internal.context():readBytes(address, length)
end

--- Reads `length` bytes as a Java byte array (1-based, `#result` for length).
function memory.read(address, length: number)
	return bytes(address, length)
end

--- Reads `length` bytes as a Luau array of numbers in 0..255.
function memory.bytes(address, length: number): { number }
	local raw = bytes(address, length)
	local out = table.create(length)
	for index = 1, length do
		out[index] = raw[index] % 256
	end
	return out
end

--- Reads `length` bytes as a Luau string, one character per byte.
function memory.string(address, length: number): string
	local raw = memory.bytes(address, length)
	local chunks = table.create(#raw)
	for index, value in raw do
		chunks[index] = string.char(value)
	end
	return table.concat(chunks)
end

--- Formats a byte array or Luau byte list as lowercase hex.
function memory.hex(source, separator: string?): string
	local values = if typeof(source) == "table" then source else internal.collect(source)
	local out = table.create(#values)
	for index, value in values do
		out[index] = string.format("%02x", value % 256)
	end
	return table.concat(out, separator or "")
end

--- Reads a NUL-terminated string. Stops at `limit` bytes (default 4096).
function memory.cstring(address, limit: number?): string
	local max = limit or 4096
	local start = internal.context():toAddress(address)
	local out = {}
	local count = 0
	local mem = internal.program():getMemory()
	for offset = 0, max - 1 do
		local value = mem:getByte(start:add(offset)) % 256
		if value == 0 then
			break
		end
		count += 1
		out[count] = string.char(value)
	end
	return table.concat(out)
end

local function memoryOf()
	return internal.program():getMemory()
end

--- Reads one unsigned byte.
function memory.u8(address): number
	return memoryOf():getByte(internal.context():toAddress(address)) % 256
end

--- Reads one signed byte.
function memory.i8(address): number
	return memoryOf():getByte(internal.context():toAddress(address))
end

--- Reads a 16-bit value using the program's endianness.
function memory.i16(address): number
	return memoryOf():getShort(internal.context():toAddress(address))
end

function memory.u16(address): number
	return memory.i16(address) % 0x10000
end

--- Reads a 32-bit value using the program's endianness.
function memory.i32(address): number
	return memoryOf():getInt(internal.context():toAddress(address))
end

function memory.u32(address): number
	return memory.i32(address) % 0x100000000
end

--- Reads a 64-bit value using the program's endianness. Values beyond 2^53 lose
--- precision, since Luau numbers are doubles.
function memory.i64(address): number
	return memoryOf():getLong(internal.context():toAddress(address))
end

--- Writes bytes at `address`. Accepts a Luau string, a Luau array of numbers, or
--- a Java byte array. Must run inside a transaction.
function memory.write(address, data)
	local payload = data
	if typeof(data) == "string" then
		local values = table.create(#data)
		for index = 1, #data do
			values[index] = string.byte(data, index)
		end
		payload = values
	end
	if typeof(payload) == "table" then
		local array = java.array(java.import("byte"), #payload)
		for index, value in payload do
			array[index] = value % 256
		end
		payload = array
	end
	internal.context():writeBytes(address, payload)
end

--- Iterates the program's memory blocks.
function memory.blocks()
	return internal.iterate(memoryOf():getBlocks())
end

--- The block containing `address`, or nil.
function memory.blockAt(address)
	return memoryOf():getBlock(internal.context():toAddress(address))
end

--- True when `address` is mapped.
function memory.contains(address): boolean
	return memoryOf():contains(internal.context():toAddress(address))
end

--- The offset `address` was loaded from in the original file, or nil when it
--- came from no file (uninitialized memory, or a block the loader synthesized).
function memory.fileOffset(address): number?
	local info = memoryOf():getAddressSourceInfo(internal.context():toAddress(address))
	if info == nil then
		return nil
	end
	local offset = info:getFileOffset()
	return if offset < 0 then nil else offset
end

--- The name of the file `address` was loaded from, or nil.
function memory.fileName(address): string?
	local info = memoryOf():getAddressSourceInfo(internal.context():toAddress(address))
	return if info ~= nil then info:getFileName() else nil
end

--- Every address a file offset was loaded to, as a Luau array. A file offset can
--- land at more than one address when a loader maps a region twice.
function memory.addressesForFileOffset(offset: number)
	return internal.collect(memoryOf():locateAddressesForFileOffset(offset))
end

return memory
