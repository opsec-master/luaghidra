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

## The `@ghidra` module

```lua
local ghidra = require("@ghidra")
```

There are no magic globals. What a script uses, it requires.

### Context

| Function | Returns |
|---|---|
| `ghidra.program()` | the open `Program`, raising if none is open |
| `ghidra.currentProgram()` | the open `Program`, or `nil` |
| `ghidra.currentAddress()` | the cursor address, or `nil` |
| `ghidra.currentLocation()` | the cursor `ProgramLocation`, or `nil` |
| `ghidra.selection()` | the selection, or `nil` when empty |
| `ghidra.tool()` | the `PluginTool`, or `nil` headless |
| `ghidra.monitor()` | the `TaskMonitor` |
| `ghidra.args()` | command-line arguments as an array |
| `ghidra.isHeadless()` | whether there is a GUI |
| `ghidra.flat()` | a `FlatProgramAPI` for the current program |
| `ghidra.script()` | the `GhidraScript` running this code |

### Output

`print` writes to the Ghidra console, streaming as the script runs.
`ghidra.log(...)` does the same through the script's writer, `ghidra.warn(...)`
writes to the error stream, and `ghidra.status(msg)` updates the task monitor.

### Addresses

```lua
ghidra.address("00401000")   -- string, with or without a space prefix
ghidra.address(0x401000)     -- number, in the default space
ghidra.address(someAddress)  -- passed through

local a = ghidra.address(0x401000)
print(a.offset, a.space.name)     -- 4198400  ram
```

Anywhere this API takes an address, all three forms work.

Addresses compare by value and by order, so they work as loop bounds and in
conditions:

```lua
if func.entry == ghidra.address(0x401000) then end
if instruction.address < func.body.maxAddress then end
```

That holds for every Java value: equality uses Java's `equals`, and `<` and `<=`
use `Comparable`, raising a clear error for values that are not comparable.

On a machine with more than one memory space — a Harvard architecture, or a
program with overlays — pass the space explicitly:

```lua
ghidra.address(0x1000, "OVL1")        -- offset within a named space
ghidra.address(0x1000, someSpace)     -- or an AddressSpace
addr:inSpace("OVL1")                  -- the same offset, elsewhere

ghidra.addressSpace()                 -- the default space
ghidra.addressSpace("OVL1")           -- by name; raises if there is no such space
ghidra.addressSpaces()                -- every space, overlays included
```

`require("@ghidra/addresses")` has the rest: listing physical spaces and
overlays, and the processor's constant, register, stack, and unique spaces.

### Iterating

Every iterator works with a generic `for` and stops with a `script cancelled`
error if the user cancels.

```lua
for func in ghidra.functions() do end
for func in ghidra.functions({ set = someAddressSet, forward = false }) do end
for func in ghidra.functions({ external = true }) do end
for symbol in ghidra.symbols({ dynamic = true }) do end
for symbol in ghidra.entryPoints() do end
for instruction in ghidra.instructions({ from = 0x401000 }) do end
for data in ghidra.data() do end
for data in ghidra.strings() do end        -- data.text is the decoded string
for block in ghidra.memoryBlocks() do end
for reference in ghidra.referencesTo(addr) do end
for reference in ghidra.referencesFrom(addr) do end
```

`ghidra.collect(source, limit?)` turns any of them — or any Java iterator,
iterable, or array — into a Luau array. `ghidra.iterate(source)` does the same
for a Java collection you got from somewhere else.

### Lookups

```lua
ghidra.functionAt(addr)          ghidra.functionContaining(addr)
ghidra.functionsNamed("main")    ghidra.symbolAt(addr)
ghidra.symbolsNamed("main")      ghidra.symbolsAt(addr)
ghidra.instructionAt(addr)       ghidra.dataAt(addr)
ghidra.codeUnitAt(addr)          ghidra.memoryBlockAt(addr)
ghidra.namespace("MyLib/Internals")
```

`...At` answers only at the exact start of something. To find what covers an
address, or what comes next, walk outwards:

```lua
ghidra.instructionContaining(addr)   ghidra.dataContaining(addr)
ghidra.codeUnitContaining(addr)

ghidra.functionAfter(addr)      ghidra.functionBefore(addr)
ghidra.instructionAfter(addr)   ghidra.instructionBefore(addr)
ghidra.dataAfter(addr)          ghidra.dataBefore(addr)
ghidra.firstFunction()          ghidra.lastFunction()

ghidra.referencedAddress(addr)  -- what this line points at
```

### Changing the database

Every change must run inside a transaction. The helper commits when the body
returns and rolls back if it raises, then re-raises so a failure is never silent.

```lua
ghidra.transaction("Rename tiny functions", function()
    for func in ghidra.functions() do
        if func.size < 16 then
            func:rename(`tiny_{func.entry}`)
        end
    end
end)
```

`program:transaction(name, body)` is the same helper on the program itself.

Other changes: `ghidra.createLabel(addr, name)`, `ghidra.createFunction(addr,
name, body)`, `ghidra.setComment(addr, text, kind)` where `kind` is `EOL`, `PRE`,
`POST`, `PLATE`, or `REPEATABLE`, `ghidra.createData(addr, type)`,
`ghidra.disassemble(addr)`, and `ghidra.clear(first, last?)`.

### Program state

```lua
ghidra.info()          -- name, language, hashes, counts, and address bounds
ghidra.analyze()       -- run the auto-analyzers and wait (not in a transaction)
ghidra.save()          -- save the program
ghidra.undo()          ghidra.redo()
ghidra.goTo(target)    ghidra.setSelection(addressSet)
ghidra.register("RAX") ghidra.registerValue("RAX", addr)   ghidra.registers()
```

### Progress and cancellation

```lua
local task = ghidra.task("Scanning", { max = ghidra.program().functionCount })
for func in ghidra.functions() do
    task:step()
end
```

`ghidra.checkCancelled()` raises `script cancelled` if the user has cancelled.
The built-in iterators call it for you; a hand-written loop should call it too.

## Luau properties on Ghidra objects

Requiring `@ghidra` registers shorthand members on Ghidra's Java classes. They
sit next to the Java API rather than replacing it, and registration fails loudly
if a name would shadow a Java member — so `func.name` and `func:getName()` are
both always available, and never mean different things.

Properties are read with `.`; methods are called with `:`.

| Class | Properties | Methods |
|---|---|---|
| `Address` | `offset`, `unsignedOffset`, `space`, `isMemory`, `isLoaded`, `isRegister`, `isStack`, `isConstant`, `isUnique`, `isExternal` | `format()`, `inSpace(space)` |
| `AddressSpace` | `name`, `bits`, `pointerSize`, `unitSize`, `spaceId`, `minAddress`, `maxAddress`, `overlayedSpace`, `physicalSpace`, `isOverlay`, `isMemory`, `isLoaded`, `isRegister`, `isStack`, `isConstant`, `isUnique`, `isExternal`, `isHash`, `isVariable`, `showsName` | `address(offset)`, `range()` |
| `AddressRange` | `minAddress`, `maxAddress`, `length`, `space` | |
| `AddressSetView` | `size`, `minAddress`, `maxAddress`, `rangeCount` | `ranges()`, `addresses(forward?)` |
| `Program` | `name`, `imageBase`, `minAddress`, `maxAddress`, `languageId`, `processor`, `bigEndian`, `pointerSize`, `compilerName`, `executablePath`, `executableFormat`, `executableMd5`, `executableSha256`, `listing`, `memory`, `symbolTable`, `functionManager`, `dataTypeManager`, `referenceManager`, `bookmarkManager`, `addressFactory`, `defaultSpace`, `globalNamespace`, `functionCount`, `symbolCount`, `changed` | `functions(forward?)`, `transaction(name, body)` |
| `Function` | `name`\*, `qualifiedName`, `entry`, `body`, `size`, `signature`, `program`, `namespace`, `comment`\*, `returnType`\*, `callingConvention`\*, `parameters`, `locals`, `variables`, `thunkedFunction`, `tags`, `stackFrame`, `inline`\*, `noReturn`\*, `external` | `rename(name, source?)`, `setSignature(prototype)`, `instructions()`, `data()`, `callers()`, `callees()`, `xrefs()`, `decompile(options?)`, `highFunction()`, `blocks()`, `complexity()`, `calls(options?)`, `callSites(options?)` |
| `Variable` / `Parameter` | `name`\*, `dataType`\*, `typeName`, `length`, `comment`\*, `storage`, `onStack`, `stackOffset`, `inRegister`, `register` | `rename(name, source?)` |
| `Symbol` | `name`\*, `qualifiedName`, `address`, `namespace`, `kind`, `source`, `primary`, `external`, `referenceCount` | `rename(name, source?)`, `moveTo(namespace)`, `xrefs()` |
| `Namespace` | `name`, `path`, `parent` | `symbols()` |
| `Reference` | `from`, `to`, `kind`, `refType`, `operand`, `source`, `isCall`, `isJump`, `isRead`, `isWrite`, `isData`, `isFlow`, `isIndirect` | `fromFunction()`, `toFunction()` |
| `CodeUnit` | `address`, `endAddress`, `length`, `bytes`, `label`, `program` | `comment(kind?)`, `setCommentText(text, kind?)`, `comments()`, `xrefsFrom()`, `xrefsTo()` |
| `Instruction` | `mnemonic`, `operandCount`, `flow`, `fallThrough`, `isCall`, `isJump`, `isTerminator`, `text` | `operands()`, `scalar(n)`, `registerOf(n)`, `flowsTo()`, `pcode()` |
| `Data` | `value`, `typeName`, `dataType`, `text`, `componentCount`, `parent`, `fieldName` | `components()` |
| `MemoryBlock` | `name`\*, `start`, `endAddress`, `size`, `readable`\*, `writable`\*, `executable`\*, `initialized`, `comment`\* | `addressSet()` |
| `Bookmark` | `address`, `kind`, `category`, `comment` | |
| `PcodeOp` | `mnemonic`, `opcode`, `output`, `inputCount`, `address`, `parent` | `inputs()`, `input(n)` |
| `Varnode` | `offset`, `size`, `address`, `def`, `high` | `descendants()` |
| `HighVariable` | `name`, `dataType`, `size`, `representative` | `instances()` |
| `HighSymbol` | `name`, `dataType`, `size`, `storage`, `variable` | |
| `CodeBlock` | `name`, `start`, `flow` | `successors()`, `predecessors()` |
| `CodeBlockReference` | `from`, `to`, `sourceBlock`, `destinationBlock`, `flow` | |
| `DataType` | `name`, `displayName`, `length`, `alignment`, `description`, `path`, `category`, `manager` | |
| `Composite` | `componentCount` | `fields()` |
| `DataTypeComponent` | `fieldName`, `offset`, `length`, `dataType`, `typeName`, `comment` | |
| `DataTypeManager` | `name`, `kind`, `typeCount`, `categoryCount`, `rootCategory` | `types()`, `find(name)` |
| `Category` | `name`, `path`, `parent`, `manager` | `types()`, `children()` |

Properties marked \* are writable, and writing one changes the database, so it
must happen inside a transaction:

```lua
ghidra.transaction("Retype", function()
    func.name = "parse_header"
    func.returnType = "int"
    func.parameters[1].name = "buffer"
end)
```

Operand and component indexes are 1-based throughout, matching Luau rather than
Java.

You can register your own members with `java.extend`:

```lua
java.extend("ghidra.program.model.listing.Function", {
    properties = {
        isLeaf = { get = function(self) return #self:callees() == 0 end },
    },
    methods = {
        tag = function(self, name) self:addTag(name) end,
    },
})
```

Extensions registered on an interface apply to every implementation.

## Focused modules

Each is reachable both ways: `require("@ghidra/memory")`, or `ghidra.memory`
after requiring the core module.

| Module | Covers |
|---|---|
| `@ghidra/addresses` | Building and combining address sets and ranges |
| `@ghidra/analysis` | Disassembly, auto-analysis, creating and clearing code |
| `@ghidra/blocks` | Basic blocks and control flow |
| `@ghidra/bookmarks` | The Bookmarks window |
| `@ghidra/datatypes` | Finding, building, and applying data types |
| `@ghidra/decompiler` | Decompilation |
| `@ghidra/io` | Reading and writing files, and JSON |
| `@ghidra/memory` | Reading and writing program memory |
| `@ghidra/pcode` | Decompiler P-code, call sites, and slices |
| `@ghidra/process` | Running other programs |
| `@ghidra/project` | The project's folders, files, and programs |
| `@ghidra/references` | Cross-references |
| `@ghidra/search` | Byte, pattern, string, and name searches |
| `@ghidra/symbols` | Symbols, labels, and namespaces |
| `@ghidra/types` | Ghidra classes by short name |
| `@ghidra/ui` | Prompts, navigation, selection |

### `@ghidra/addresses`

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

### `@ghidra/memory`

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

### `@ghidra/search`

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

### `@ghidra/references`

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

### `@ghidra/symbols`

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

### `@ghidra/datatypes`

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

#### Managers and archives

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

### `@ghidra/decompiler`

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

### `@ghidra/blocks`

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

### `@ghidra/pcode`

```lua
local pcode = require("@ghidra/pcode")

local high = pcode.high(func)
for op in pcode.ops(high) do              -- or pcode.ops(func) to decompile first
    print(op.mnemonic, op.output, #op:inputs())
end
pcode.blocks(high)   pcode.symbols(high)   pcode.parameters(high)
```

Raw, pre-decompiler P-code for one instruction is `instruction:pcode()`.

#### Call sites and their arguments

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

#### Slices

What a value flows into, and what it came from:

```lua
pcode.forwardSlice(varnode)     pcode.backwardSlice(varnode)
pcode.forwardSliceOps(varnode)  pcode.backwardSliceOps(varnode)
```

### `@ghidra/analysis`

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

### `@ghidra/bookmarks`

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

### `@ghidra/io`

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

### `@ghidra/process`

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

### `@ghidra/ui`

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

### `@ghidra/project`

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

### `@ghidra/types`

Ghidra classes by short name, imported on first use:

```lua
local types = require("@ghidra/types")

func:setName("main", types.SourceType.USER_DEFINED)
local ifc = types.DecompInterface()
local Anything = types.of("ghidra.some.package.Anything")
```

## Reaching into Java

`@ghidra` is meant to cover ordinary scripting on its own; reaching for `java`
should be the exception, not the routine. When you do need something the modules
have not wrapped, the `java` module reaches the rest of the JVM directly — no
wrapper to unwrap, and values move freely between the two layers.

```lua
local System = java.import("java.lang.System")
print(System:currentTimeMillis())            -- static method
print(java.import("java.lang.Integer").MAX_VALUE)

local list = java.new(java.import("java.util.ArrayList"))
list:add("a")
print(list:size(), tostring(list))

local analysis = java.import("ghidra.app.plugin.core.analysis.AutoAnalysisManager")
    :getAnalysisManager(ghidra.program())
analysis:reAnalyzeAll(nil)
```

Java values arrive as one of three userdata types:

- `jclass` — from `java.import`. Supports `clazz.staticField`,
  `clazz.staticField = v`, `clazz:staticMethod(...)`, `clazz(...)` to construct,
  inner-class lookup, and `clazz.class`.
- `jobject` — an instance. Supports `obj.field`, `obj.field = v`, and
  `obj:method(...)`.
- `jarray` — an array. Supports `arr[i]` and `arr[i] = v` (1-based, bounds
  checked), `#arr`, `arr:method(...)`, and `for index, value in arr do`, the same
  as a Luau array.

| Function | Description |
|---|---|
| `java.import(name)` | Import a class |
| `java.new(class, ...)` | Construct an instance |
| `java.array(class, length)` | Create a one-dimensional array |
| `java.luaify(value)` | Convert a Java value to a Lua value where possible |
| `java.extend(className, members)` | Register Luau properties and methods on a class |
| `java.proxy(interfaces, handler)` | Implement Java interfaces in Luau |
| `java.caught()` | The most recent Java `Throwable`, or `nil` |

### Implementing Java interfaces

`java.proxy` closes the other direction: when a Ghidra API wants a callback, a
Luau function can be it.

```lua
-- A functional interface takes a bare function.
local isLong = java.proxy("java.util.function.Predicate", function(value)
    return #value > 3
end)
list:removeIf(isLong)

-- Several methods, or several interfaces, take a table of functions.
local comparator = java.proxy("java.util.Comparator", {
    compare = function(left, right) return #left - #right end,
})
list:sort(comparator)
```

Errors raised inside a handler propagate out of the Java call, and `tostring`,
`equals`, and `hashCode` work without a handler.

Because a Luau state is single-threaded, a proxy may only be called from the
thread running its interpreter. Synchronous callbacks — a predicate passed to a
query, a comparator passed to a sort — are exactly that. One that hands work to a
background thread is not, and the call fails with a clear error rather than
corrupting the interpreter.

Booleans, numbers, and strings convert automatically in both directions; other
objects stay as `jobject`. Overloads resolve from the runtime types of the
arguments. A Java exception becomes a Lua error and is retrievable afterwards:

```lua
local ok = pcall(function()
    java.import("java.lang.Integer"):parseInt("xx")
end)
print(java.caught():getClass():getName())    -- java.lang.NumberFormatException
```

Member lookup on a Java value tries the Java field, then the Java method, then a
registered Luau extension. A name that resolves to nothing is `nil`, so
`if obj.maybeThere then` is a safe test.

Not ported from [luajava](https://github.com/gudzpoz/luajava): package (`.*`)
imports, `java.method` with explicit signatures, `java.unwrap`, `java.loadlib`,
`java.detach`, and multi-dimensional arrays. `java.caught()`
holds the last throwable until the next Java exception rather than clearing on a
successful call.

## Writing scripts

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

## Development

```sh
gradle luaTest        # run the Luau suite headlessly
gradle buildExtension # build dist/<ghidra>_LuaGhidra.zip
gradle runGhidraTemp  # launch Ghidra with the extension in a scratch profile
```

`gradle luaTest` builds the native bridge, starts Ghidra headlessly, creates a
small in-memory program — one memory block holding two disassembled x86-64
functions, one of which calls the other — and runs every file in `src/test/luau`
plus every example script against a fresh copy of it. Console completion and the editor setup are checked
from `LuauTestRunner` because they have no Luau-visible surface.

### Layout

| Path | Contents |
|---|---|
| `src/main/java/luaghidra/` | plugin, console, script provider, runtime |
| `src/main/java/luaghidra/bridge/` | reflection back-end for the `java` module |
| `src/main/native/` | JNI bridge, `java` module, `require`, Luau helpers |
| `src/main/resources/luaghidra/modules/ghidra/` | the `@ghidra` Luau modules |
| `.../ghidra/extensions/` | the Luau members registered on Ghidra's classes |
| `ghidra_scripts/` | example scripts, installed with the extension |
| `src/test/luau/` | the Luau test suite |
| `third_party/luau` | the Luau submodule |

### Native build

The build configures Luau with CMake and Ninja, links the static libraries into
one shared library, and stages it under `os/<platform>`:

```sh
gradle stageBridgeNative
```

Pass `-PskipLuauNative=true` to package only Java and resources while iterating
on extension metadata.

The Java side loads the bridge through `LuauNativeBridge.load()`, which checks
the `luaghidra.library.path` system property, then Ghidra's extension `os/`
directory, then `java.library.path`.

### Releases

`.github/workflows/release.yml` builds the bridge on five runners — one per
Ghidra `os/<platform>` directory — then packages all of them into a single
extension zip and attaches it to a GitHub release.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

Run it from the Actions tab (`workflow_dispatch`) to get the zip as a build
artifact without publishing a release; the Ghidra version to build against is an
input there.

The native jobs cross-build through three Gradle properties, which are also
useful locally:

| Property | Purpose |
|---|---|
| `-PnativePlatform=` | the `os/<platform>` directory to stage into |
| `-PcmakeGenerator=` | CMake generator (`Ninja` by default, MSVC on Windows) |
| `-PcmakeArgs=` | `;`-separated extra CMake arguments |

```sh
gradle stageBridgeNative -PnativePlatform=mac_x86_64 \
  -PcmakeArgs=-DCMAKE_OSX_ARCHITECTURES=x86_64
```

### Source-tree development

This repository is expected to sit beside a Ghidra checkout. Add `LuaGhidra` to
`../ghidra/ghidra.repos.config` and run Gradle from the Ghidra source tree; the
project is included as `:LuaGhidra` and targets the same Java version.
