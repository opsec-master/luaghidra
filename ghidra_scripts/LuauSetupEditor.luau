--@category Luau
--@description Sets a script directory up for editing .luau files with type checking.

-- Writes a .luaurc and a copy of the @ghidra modules into a script directory so
-- that luau-lsp (https://github.com/JohnnyMorganz/luau-lsp) resolves
-- require("@ghidra") and can offer types and completion while you write.
--
-- Run it again after upgrading the extension to refresh the copy.

local ghidra = require("@ghidra")
local ui = require("@ghidra/ui")

local home = java.import("java.lang.System"):getProperty("user.home")
local directory = ui.askString(
	"Set up Luau editing",
	"Script directory to configure:",
	`{home}/ghidra_scripts`
)

local modules = require("@host"):setUpEditor(directory)

print(`wrote {directory}/.luaurc`)
print(`extracted the @ghidra modules to {modules}`)
print("point your editor's luau-lsp at that directory to get types and completion")
