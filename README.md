# LuaGhidra

Luau scripting for Ghidra: an interactive console, a `.luau` script provider, and
a scripting API that keeps Ghidra's full Java surface within reach.

```lua
local ghidra = require("@ghidra")

for func in ghidra.functions() do
    print(`{func.entry}  {func.name}`)
end
```

## What you get

- **An interpreter console** with persistent state, multi-line input, tab
  completion, and a cancel button (`Window > LuaGhidra`).
- **`.luau` scripts** in the Script Manager and headless, run through the same
  API as the console.
- **`require("@ghidra")`** — the scripting API: programs, addresses, functions,
  symbols, references, memory, data types, the decompiler, basic blocks, P-code,
  search, bookmarks, analysis, files, transactions, and prompts.
- **`java.import(...)` and `java.proxy(...)`** — direct reflection into the JVM,
  in both directions, for the rare thing the modules do not cover.

Everything the modules return is a real Ghidra Java object. `func.name` and
`func:getName()` both work on the same value, and dropping down to the Java API
is always a method call away rather than an unwrapping step.

## Installing

Build the extension against a Ghidra installation:

```sh
gradle -PGHIDRA_INSTALL_DIR=/path/to/ghidra_<version> buildExtension
```

Install the zip from `dist/` with `File > Install Extensions`, restart Ghidra,
then enable **LuaGhidra Interpreter** under
`File > Configure > Configure All Plugins` (category *Common*). The console opens
from `Window > LuaGhidra`.

## A first script

There are no magic globals: what a script uses, it requires. Changes to the
database run inside a transaction, and every iterator stops when the user
cancels.

```lua
local ghidra = require("@ghidra")
local pcode = require("@ghidra/pcode")

ghidra.transaction("Rename handlers", function()
    for call in pcode.callsTo("register_function") do
        local name = pcode.stringOf(call.args[2])
        local handler = ghidra.functionAt(pcode.addressOf(call.args[3]))
        if name and handler then
            handler:rename(name)
        end
    end
end)
```

Drop it in a Ghidra script directory as a `.luau` file and it shows up in the
Script Manager, or runs headlessly:

```sh
analyzeHeadless /projects Project -process binary -postScript MyScript.luau
```

## Documentation

| Guide | Contents |
|---|---|
| [The `@ghidra` API](docs/api.md) | Context, addresses, iterators, lookups, transactions, and the Luau members registered on Ghidra's classes |
| [Focused modules](docs/modules.md) | `@ghidra/memory`, `search`, `decompiler`, `pcode`, `datatypes`, `project`, `ui`, and the rest |
| [Reaching into Java](docs/java.md) | `java.import`, `java.new`, `java.extend`, and implementing Java interfaces in Luau |
| [Writing scripts](docs/scripts.md) | Script metadata, `require`, the bundled examples, editor type checking, and errors |
| [Development](docs/development.md) | Building, the test suite, repository layout, the native bridge, and releases |

## Development

```sh
gradle luaTest        # run the Luau suite headlessly
gradle buildExtension # build dist/<ghidra>_LuaGhidra.zip
gradle runGhidraTemp  # launch Ghidra with the extension in a scratch profile
```

See [docs/development.md](docs/development.md) for the rest.
