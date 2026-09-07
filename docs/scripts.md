# Writing scripts

[LuaGhidra](../README.md) · [API](api.md) · [Modules](modules.md) · [Java](java.md) · **Scripts** · [Development](development.md)

Any `.luau` file in a Ghidra script directory is picked up by the Script Manager
and runs headlessly:

```sh
analyzeHeadless /projects Project -process binary -postScript MyScript.luau
```

Script metadata uses Luau comments:

```lua
--@category Luau.Examples
--@description Prints every function with its entry point and size.

local ghidra = require("@ghidra")
```

`require` takes two shapes:

- `require("@ghidra")`, `require("@ghidra/memory")` — modules that ship with the
  extension.
- `require("./helpers")`, `require("../lib/util")` — files next to the script.

A bare `require("helpers")` is rejected, so a script's dependencies are never
ambiguous. Modules are cached per interpreter and must return a value.

The examples in `ghidra_scripts/` are installed with the extension:

| Script | What it does |
|---|---|
| `LuauListFunctions.luau` | Prints every function with its entry point and size |
| `LuauRenameDefaults.luau` | Renames `FUN_*` functions after a string they reference |
| `LuauDecompileFunction.luau` | Decompiles the function under the cursor |
| `LuauCallArguments.luau` | Prints every call with the arguments the decompiler found |
| `LuauFindStrings.luau` | Prints defined strings matching a pattern |
| `LuauFindPattern.luau` | Searches for a byte pattern and bookmarks every hit |
| `LuauExportFunctions.luau` | Writes a JSON report of every function |
| `LuauSetupEditor.luau` | Configures a script directory for type checking |
| `LuauDoctor.luau` | Reports what the runtime can see, for diagnosing setup |

## Type checking in an editor

Run `LuauSetupEditor.luau` and point it at your script directory. It writes a
`.luaurc` and extracts the `@ghidra` modules alongside your scripts, so
[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) resolves `require("@ghidra")`
and offers types and completion. Run it again after upgrading the extension.

The interpreter always reads the modules from inside the extension; the extracted
copy exists only for the editor.

## Errors

Runtime errors carry a Luau traceback:

```text
@ghidra:41: no program is open
@ghidra/internal/host:24 function context
@ghidra:41 function program
/Users/me/ghidra_scripts/MyScript.luau:5
```

A Java exception thrown from a bridge call becomes a Lua error with the Java
message, catchable with `pcall` and inspectable with `java.caught()`.

