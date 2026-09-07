-- Luau properties and methods registered on Ghidra's Java classes.
--
-- These sit alongside the Java API rather than replacing it: `func:getName()`
-- and `func.name` both work, and every Java method stays reachable. Registration
-- fails loudly if a name would shadow a Java member, so the two never collide.

require("@ghidra/extensions/address")
require("@ghidra/extensions/program")
require("@ghidra/extensions/function")
require("@ghidra/extensions/listing")
require("@ghidra/extensions/symbol")
require("@ghidra/extensions/memory")
require("@ghidra/extensions/datatypes")
require("@ghidra/extensions/pcode")

return true
