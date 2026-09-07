# The `@ghidra` API

[LuaGhidra](../README.md) · **API** · [Modules](modules.md) · [Java](java.md) · [Scripts](scripts.md) · [Development](development.md)

The core module and the Luau members it registers on Ghidra's classes.

```lua
local ghidra = require("@ghidra")
```

There are no magic globals. What a script uses, it requires.

## Context

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

## Output

`print` writes to the Ghidra console, streaming as the script runs.
`ghidra.log(...)` does the same through the script's writer, `ghidra.warn(...)`
writes to the error stream, and `ghidra.status(msg)` updates the task monitor.

## Addresses

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

## Iterating

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

## Lookups

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

## Changing the database

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

## Program state

```lua
ghidra.info()          -- name, language, hashes, counts, and address bounds
ghidra.analyze()       -- run the auto-analyzers and wait (not in a transaction)
ghidra.save()          -- save the program
ghidra.undo()          ghidra.redo()
ghidra.goTo(target)    ghidra.setSelection(addressSet)
ghidra.register("RAX") ghidra.registerValue("RAX", addr)   ghidra.registers()
```

## Progress and cancellation

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

