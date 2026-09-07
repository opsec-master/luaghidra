# Focused modules

[LuaGhidra](../README.md) · [API](api.md) · **Modules** · [Java](java.md) · [Scripts](scripts.md) · [Development](development.md)

Each is reachable both ways: `require("@ghidra/memory")`, or `ghidra.memory`
after requiring the core module.

| Module | Covers |
|---|---|
| [`@ghidra/addresses`](#ghidraaddresses) | Building and combining address sets and ranges |
| [`@ghidra/analysis`](#ghidraanalysis) | Disassembly, auto-analysis, creating and clearing code |
| [`@ghidra/blocks`](#ghidrablocks) | Basic blocks and control flow |
| [`@ghidra/bookmarks`](#ghidrabookmarks) | The Bookmarks window |
| [`@ghidra/datatypes`](#ghidradatatypes) | Finding, building, and applying data types |
| [`@ghidra/decompiler`](#ghidradecompiler) | Decompilation |
| [`@ghidra/io`](#ghidraio) | Reading and writing files, and JSON |
| [`@ghidra/memory`](#ghidramemory) | Reading and writing program memory |
| [`@ghidra/pcode`](#ghidrapcode) | Decompiler P-code, call sites, and slices |
| [`@ghidra/process`](#ghidraprocess) | Running other programs |
| [`@ghidra/project`](#ghidraproject) | The project's folders, files, and programs |
| [`@ghidra/references`](#ghidrareferences) | Cross-references |
| [`@ghidra/search`](#ghidrasearch) | Byte, pattern, string, and name searches |
| [`@ghidra/symbols`](#ghidrasymbols) | Symbols, labels, and namespaces |
| [`@ghidra/types`](#ghidratypes) | Ghidra classes by short name |
| [`@ghidra/ui`](#ghidraui) | Prompts, navigation, selection |

## `@ghidra/addresses`

```lua
local addresses = require("@ghidra/addresses")

-- Any mix of addresses, ranges, sets, and { first, last } pairs.
local set = addresses.set(func.body, 0x401300, { 0x401400, 0x40140f })

addresses.union(a, b)      addresses.intersect(a, b)   addresses.subtract(a, b)
addresses.range(first, last)                           addresses.empty()
addresses.ranges(set)      addresses.each(set)         addresses.program()
addresses.of(value, space?)
```

Results are Ghidra `AddressSet`s, so their Java methods work too:
`set:union(other)`, `set:contains(addr)`, `set:isEmpty()`.

Address spaces:

```lua
addresses.space()            -- the default space
addresses.space("OVL1")      -- by name; raises, listing the real spaces, if absent
addresses.spaces()           -- every space, overlays included
addresses.physicalSpaces()   -- memory spaces, without overlays
addresses.overlays()         -- just the overlay spaces
addresses.hasMultipleSpaces()

addresses.constantSpace()    addresses.registerSpace()
addresses.stackSpace()       addresses.uniqueSpace()
addresses.factory()          -- the AddressFactory, for the rest
```

An overlay knows what it overlays and which addresses it actually defines:

```lua
for _, space in addresses.overlays() do
    print(space.name, space.overlayedSpace.name, space.definedAddresses.size)
end
```

## `@ghidra/memory`

```lua
local memory = require("@ghidra/memory")

memory.u8(addr)     memory.i8(addr)
memory.u16(addr)    memory.i16(addr)
memory.u32(addr)    memory.i32(addr)    memory.i64(addr)

memory.read(addr, 16)      -- Java byte array
memory.bytes(addr, 16)     -- Luau array of 0..255
memory.string(addr, 16)    -- Luau string, one character per byte
memory.cstring(addr)       -- NUL-terminated string
memory.hex(memory.read(addr, 4))   -- "deadbeef"

memory.write(addr, "\xde\xad")     -- string, array, or Java byte array
memory.blocks()  memory.blockAt(addr)  memory.contains(addr)
```

Multi-byte reads use the program's endianness.

Addresses and file offsets convert both ways, which is what a script needs when
it hands the binary to an outside tool — `binwalk`, `yara`, a hash database — and
has to map what came back onto the listing:

```lua
memory.fileOffset(addr)               -- where it came from on disk, or nil
memory.fileName(addr)                 -- which file that was
memory.addressesForFileOffset(0x700)  -- and back, as an array: a file offset can
                                      -- be mapped to more than one address
```

## `@ghidra/search`

```lua
local search = require("@ghidra/search")

for hit in search.bytes("\x55\x48\x89\xe5") do end
for hit in search.bytes({ 0x55, 0x48, nil, 0xe5 }) do end   -- nil is a wildcard
for hit in search.pattern("55 48 ?? e5") do end             -- ?? is a wildcard
search.firstPattern("55 48 ?? e5", { from = 0x401000 })

for data in search.strings("password") do end       -- Luau patterns
for func in search.functions("^FUN_") do end
for symbol in search.symbols("alloc") do end
for instruction in search.instructions("^CALL") do end
```

Byte searches take `{ from = addr, limit = n }`.

## `@ghidra/references`

```lua
local refs = require("@ghidra/references")

for reference in refs.to(addr) do print(reference.from, reference.kind) end
for reference in refs.from(addr) do end
for call in refs.callsTo(func.entry) do end        -- call sites only
refs.countTo(addr)

ghidra.transaction("Reference", function()
    refs.add(fromAddr, toAddr, "DATA", 1)   -- operand is 1-based, or nil
    refs.add(fromAddr, toAddr, "READ", 1, "ANALYSIS")   -- and its source type
    refs.remove(reference)
    refs.removeAllFrom(addr)   refs.removeAllTo(addr)
    refs.setPrimary(reference)
end)
```

## `@ghidra/symbols`

```lua
local symbols = require("@ghidra/symbols")

symbols.at(addr)              symbols.allAt(addr)
symbols.named("main")         symbols.entryPoints()
symbols.all({ dynamic = true, name = ..., namespace = ..., set = ... })

ghidra.transaction("Label", function()
    local ns = symbols.namespace("MyLib/Internals")   -- finds or creates
    symbols.createLabel(addr, "init", ns)
    symbols.remove(symbol)
end)

symbols.findNamespace("MyLib/Internals")   -- nil when it does not exist
symbols.global()
```

## `@ghidra/datatypes`

```lua
local dt = require("@ghidra/datatypes")

dt.resolve("int")        dt.resolve("char[8]")     dt.resolve("char *")
dt.find("MyStruct")      dt.path("/Cat/MyStruct")  dt.all()
dt.composites()          dt.functionDefinitions()
dt.instances("Header")   -- every place the type has been applied

ghidra.transaction("Apply types", function()
    dt.struct("Header", {
        { name = "magic", type = "char[4]" },
        { name = "size", type = "uint", comment = "in bytes" },
    })
    dt.union("Either", { { name = "asInt", type = "int" } })
    dt.enum("Flags", { NONE = 0, READ = 1, WRITE = 2 }, 1)
    dt.pointer("Header")     dt.array("int", 4)
    dt.apply(0x402000, "Header")
    dt.clear(0x402100)
end)
```

Anywhere a data type is expected you may pass a `DataType` or a string in
Ghidra's notation.

### Managers and archives

A program sees several data type managers at once: its own, Ghidra's built-in
archive, and any file or project archives that are open. Lookups search all of
them, and applying a type from an archive copies it into the program for you —
so most scripts never have to think about which manager a type came from.

```lua
dt.manager()      -- the program's; where new types are stored
dt.builtins()     -- Ghidra's built-in archive
dt.managers()     -- all of them, program first
dt.archives()     -- just the open archives

dt.openArchive("/path/to/types.gdt")   -- works headless; returns a manager
dt.closeArchive(manager)

dt.find("Header")             -- searches every manager
dt.find("Header", someArchive)  -- or just one
dt.findAll("Header")          -- { type = ..., manager = ... } for each match
dt.import(archiveType)        -- copy a type into the program, in a transaction
```

Every type says where it lives, which is what makes the copy explicit when you
want it to be:

```lua
local header = dt.find("Header")
print(header.manager.name, header.manager.kind)   -- "types.gdt"  FILE
```

Categories, for walking an archive's structure:

```lua
dt.rootCategory(manager?)     dt.category("/Cat/Sub", manager?)
for category in dt.categories(manager?) do
    print(category.path, #category:types())
end
```

## `@ghidra/decompiler`

```lua
local result = func:decompile()          -- or ghidra.decompile(func, { timeout = 60 })
if result.ok then
    print(result.c)
    print(result.signature)
    local high = result.highFunction      -- for P-code work
else
    ghidra.warn(result.error)
end
```

Failures come back as `{ ok = false, error }` rather than raising, so the
ordinary "this one would not decompile" case needs no `pcall`. The decompiler
process starts on first use and is reused for the rest of the session.

## `@ghidra/blocks`

```lua
local blocks = require("@ghidra/blocks")

for block in blocks.of(func) do          -- or an address set, or nothing for all
    for successor in blocks.successors(block) do end
    for predecessor in blocks.predecessors(block) do end
    for flow in blocks.flowsOut(block) do end     -- carries the flow type
end

blocks.at(addr)   blocks.containing(addr)
```

Blocks are `CodeBlock`s, which are address sets, so `block.size`,
`block.minAddress`, and `block:contains(addr)` all work, and `block.name`,
`block.start`, `block:successors()`, and `block:predecessors()` are there too.

## `@ghidra/pcode`

```lua
local pcode = require("@ghidra/pcode")

local high = pcode.high(func)
for op in pcode.ops(high) do              -- or pcode.ops(func) to decompile first
    print(op.mnemonic, op.output, #op:inputs())
end
pcode.blocks(high)   pcode.symbols(high)   pcode.parameters(high)
```

Raw, pre-decompiler P-code for one instruction is `instruction:pcode()`.

### Call sites and their arguments

Most P-code work starts at a call: what was passed to `sprintf` here, which
handler was registered under which name there. Both directions are iterators over
the same shape, and each calling function is decompiled once.

```lua
for call in pcode.calls(func) do end          -- the calls a function makes
for call in pcode.callsTo("sprintf") do end   -- every call site of a function
```

A call is `{ at, target, targetFunction, args, caller, op, indirect }`, where
`args` is a Luau array of `Varnode`s and `at` is the call instruction's address.
`func:calls()` and `func:callSites()` are the same two iterators on the function.

Arguments are varnodes, so reading a value off one is its own step:

```lua
pcode.constant(varnode)    -- the number it holds, following copies and casts
pcode.addressOf(varnode)   -- that number as an Address, or nil
pcode.stringOf(varnode)    -- the string it points at, or nil
```

Which makes the usual "rename handlers from the name they registered with" script
the loop it should be:

```lua
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

### Slices

What a value flows into, and what it came from:

```lua
pcode.forwardSlice(varnode)     pcode.backwardSlice(varnode)
pcode.forwardSliceOps(varnode)  pcode.backwardSliceOps(varnode)
```

## `@ghidra/analysis`

```lua
local analysis = require("@ghidra/analysis")

ghidra.transaction("Disassemble", function()
    analysis.disassemble(addr)
    analysis.createFunction(addr, "entry")
    analysis.removeFunction(addr)
    analysis.clear(first, last)      -- or one address, or an address set
    analysis.setFallThrough(addr, target)
    analysis.setThunk(func, target)
end)

analysis.run()          -- auto-analysis; manages its own transactions
analysis.runChanges()
analysis.reanalyze(addressSet)
analysis.manager()      -- the AutoAnalysisManager, for individual analyzers

analysis.demangle("_ZN3foo3barEv")       -- "__rustcall foo::bar(void)", or nil
analysis.demangledName("_ZN3foo3barEv")  -- "bar", or nil
```

The analyzers Ghidra will run, and their settings — the Analysis Options dialog,
by its option names:

```lua
analysis.options()                    -- every option, name to current value
analysis.option("Stack")              -- one, or nil when there is no such option
analysis.optionDescription("Stack")

ghidra.transaction("Configure analysis", function()
    analysis.setOption("Stack", false)
    analysis.setOption("ASCII Strings.Minimum String Length", "LEN_8")
    analysis.resetOptions({ "Stack" })   -- or resetOptions() for all of them
end)
```

## `@ghidra/bookmarks`

```lua
local bookmarks = require("@ghidra/bookmarks")

for mark in bookmarks.all() do end          -- or bookmarks.all("Note")
bookmarks.at(addr)     bookmarks.kinds()

ghidra.transaction("Mark", function()
    bookmarks.add(addr, "interesting", "Note", "reads the key")
    bookmarks.remove(mark)
    bookmarks.removeKind("Note")
end)
```

## `@ghidra/io`

Luau ships without a file library, so this fills that gap. `~` expands to the
user's home directory.

```lua
local io = require("@ghidra/io")

io.read(path)         io.readLines(path)     io.lines(path)
io.write(path, text)  io.append(path, text)  -- parents are created as needed
io.exists(path)       io.isDirectory(path)   io.list(path)
io.remove(path)       io.makeDirectory(path)

io.toJson(value, indent?)      io.writeJson(path, value)
```

A path is a string or the `java.io.File` a prompt returns, so what `ui.askFile`
hands back goes straight into `io.write`.

## `@ghidra/process`

Reverse engineering scripts lean on the tools already installed beside Ghidra —
`yara`, `binwalk`, a demangler, a packer detector — and Luau has no `os.execute`.

```lua
local process = require("@ghidra/process")

process.output({ "yara", rules, path })       -- what it printed; raises on failure
for line in process.lines({ "nm", "-U", path }) do end
process.run({ "binwalk", "-c", path })        -- { ok, code, stdout, stderr }
process.which("yara")                         -- its path, or nil when not installed
```

A command is an array — the program, then one argument each — and never reaches a
shell, so spaces, quotes, and globs in an argument are passed through as written.
`run` returns a result instead of raising, because plenty of tools use a non-zero
exit to say "nothing found"; `output` and `lines` raise, for the commoner "answer
or stop" shape. Options are `input`, `cwd`, `env`, `timeout` in seconds, and
`stderr = false` to collect the error stream separately instead of merged.

## `@ghidra/ui`

```lua
local ui = require("@ghidra/ui")

ui.askString(title, prompt, default?)   ui.askInt(title, prompt)
ui.askDouble(title, prompt)             ui.askAddress(title, prompt, default?)
ui.askBytes(title, prompt)              -- "AA BB 00 1C" as an array of numbers
ui.askYesNo(title, prompt)              ui.askChoice(title, prompt, choices, default?)
ui.askFile(title, label?)               ui.askDirectory(title, label?)
ui.askProjectFolder(prompt)             ui.askProgram(title)
ui.askDomainFile(title)                 ui.askLanguage(title, label?)
ui.popup(message)                       -- prints instead when headless
ui.goTo(addressOrFunctionOrSymbol)      ui.status(message)
ui.setSelection(addressSet)             ui.clearSelection()
```

One dialog for several values, rather than a prompt each:

```lua
local answers = ui.askValues("Report options", {
    { name = "Name", kind = "string" },
    { name = "Max Results", kind = "int", default = 100 },
    { name = "Priority", kind = "choice", choices = { "Low", "High" } },
    { name = "Output", kind = "directory" },
})
print(answers.Name, answers["Max Results"], answers.Priority)
```

Field kinds are `string`, `int`, `long`, `double`, `boolean`, `file`,
`directory`, `address`, `language`, `choice`, `program`, `projectFile`, and
`projectFolder`. The result is keyed by field name, and a field the user left
empty is `nil`.

Prompts raise when the user cancels. Headless runs answer them from the script's
`.properties` file, the same way Java scripts do.

## `@ghidra/project`

Scripts that work across a whole project — rename everything under a folder, run
an analysis over every binary, collect one report from many programs — have to
borrow each program from its file and give it back afterwards. This module does
that part.

```lua
local project = require("@ghidra/project")

for program, file in project.programs() do        -- opens and releases each one
    print(file:getPathname(), program.functionCount)
end

project.name()          project.root()          project.folder("/samples")
project.folders(folder?)                        project.files(folder?)
project.programs(folder?, { readOnly = true })
project.withProgram(file, function(program) ... end)
project.open(file)      project.close(program)  project.save(program, comment?)
project.isProgram(file) project.fileOf(program) project.current()
```

The program a `programs` loop hands you is released as soon as the loop moves on,
so anything you want to keep has to be read inside the body. Files that are
versioned but not checked out are skipped, since nothing may write to them.
Saving the program the script itself was started on fails — the tool is holding
it open — so a project-wide script should skip it or be run with nothing open.

Running another script, which is how the bundled batch scripts do their work:

```lua
ghidra.runScript("AddCommentToProgramScript.java")
ghidra.runScript("Report.luau", { "--json" })
```

## `@ghidra/types`

Ghidra classes by short name, imported on first use:

```lua
local types = require("@ghidra/types")

func:setName("main", types.SourceType.USER_DEFINED)
local ifc = types.DecompInterface()
local Anything = types.of("ghidra.some.package.Anything")
```

