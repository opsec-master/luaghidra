# Porting public Ghidra scripts to Luau

A survey of what it takes to write a real Ghidra script in `@ghidra` rather than
in Java or Python, and what the API was missing. Twenty-six widely used scripts
were ported and twenty of them run against real binaries; the friction each one
hit is recorded below, along with what was added in response. The bundled set is
too large to port whole -- Ghidra 12.1.2 ships 336 scripts -- so all 336 were
parsed for the API they use, and that ranking chose the second round of ports.

## Method

Three sources, chosen because they are what people actually copy from:

- **Ghidra's own bundled scripts** (`Ghidra/Features/*/ghidra_scripts` in 12.1.2).
  These are the examples every new script starts from.
- **0xdea's [ghidra-scripts](https://github.com/0xdea/ghidra-scripts)** and
  **ghidraninja's [ghidra_scripts](https://github.com/ghidraninja/ghidra_scripts)**,
  the two most-recommended third-party collections.
- **HackOvert's [GhidraSnippets](https://github.com/HackOvert/GhidraSnippets)**,
  the de-facto cookbook for Ghidra's Python API.

Each port is a faithful translation: same behaviour, same prompts, same output,
written the way the `@ghidra` documentation suggests rather than by transcribing
Java calls one for one. Where the API had no answer, the port reached for
`java.import` and the reach was recorded as a gap.

The ports ran headless against an arm64 Mach-O built from a small C program with
the shapes these scripts look for — insecure calls, a dispatch table registering
handlers by name, a switch statement, string constants:

```sh
gradle installGhidraTempExtension -PluaGhidraTempSettingsDir=/tmp/ghidra-settings
GHIDRA_JAVA_OPTIONS=-Dapplication.settingsdir=/tmp/ghidra-settings \
  analyzeHeadless /tmp/proj Ports -import ./vuln -postScript PortRhabdomancer.luau -scriptPath ./ports
```

### Covering the bundled set

Ghidra 12.1.2 ships 336 script files; picking a dozen by hand says little about
the rest. So every one of them was also parsed for the API it uses — the
`GhidraScript` helpers it calls and the Ghidra classes it imports — and the
result ranked. That is what decided the second round of ports: the clusters below
are the ones the corpus asks for most, not the ones that looked interesting.

| Used by | Surface | Covered before |
|---|---|---|
| ~30 scripts | `askProjectFolder`, `askProgram`, `findPrograms`, `DomainFile`, `DomainFolder` | nothing |
| 13 scripts | `askValues` / `GhidraValuesMap` | nothing |
| ~15 scripts | `getFunctionBefore/After`, `getDataAfter`, `getInstructionContaining`, ... | nothing |
| 10 scripts | `createTableChooserDialog` and its column and executor interfaces | nothing |
| 46 imports | `Msg` and `popup` | `print`/`warn` only |
| 8 scripts | `ghidra.pcode.exec` emulation | nothing |
| 7 scripts | `DecompilerUtils` | nothing (now covered) |
| 7 scripts | `GraphDisplayBroker` | nothing |
| 6 scripts | `runScript` | nothing |

The single biggest finding from that pass: **292 of the 336 scripts extend
`GhidraScript`, and `@ghidra` had no way to reach the script object at all.**
`ghidra.flat()` gave you the `FlatProgramAPI`, but everything that lives on
`GhidraScript` itself — the project, the tool state, `runScript`, half the
prompts — was unreachable except through the internal `@host` module.

## What was ported

| Script | Origin | Outcome |
|---|---|---|
| `ExportFunctionInfoScript.java` | Ghidra | Clean; `ui.askFile` handed to `io.writeJson` needed a `tostring` |
| `ComputeCyclomaticComplexity.java` | Ghidra | Needed `java.import` for `CyclomaticComplexity` |
| `PrintFunctionCallTreesScript.java` | Ghidra | Clean |
| `RecursiveStringFinder.py` | Ghidra | Found no strings until the port dropped to `reference.refType:isData()` |
| `CountAndSaveStrings.java` | Ghidra | Clean, except `data:getDefaultValueRepresentation()` |
| `XorMemoryScript.java` | Ghidra | Parsed the hex pattern by hand: no `askBytes` |
| `RegisterTouchesPerFunction.java` | Ghidra | Raw `getResultObjects`/`getInputObjects`, and their arrays would not iterate |
| `LocateMemoryAddressesForFileOffset.py` | Ghidra | Whole script was raw Java: no file-offset API |
| `GetAndSetAnalysisOptionsScript.java` | Ghidra | Whole script was raw Java: no analyzer-option API |
| `Rhabdomancer.java` | 0xdea | Ran; `ghidra.functions({ external = true })` misled the port |
| `Haruspex.java` | 0xdea | Clean, and shorter: `func:decompile()` replaces the `DecompInterface` setup |
| `golang_renamer.py` | ghidraninja | Ported; took its "not a Go binary" path on the test target |
| `swift_demangler.py` | ghidraninja | Blocked on running a subprocess (written, not run: no Swift binary at hand) |
| `yara.py`, `binwalk.py` | ghidraninja | Read, not ported: blocked on the same, plus file-offset to address mapping |
| Call arguments at cross references | GhidraSnippets | 40 lines of `HighFunction` plumbing |
| Rename functions based on strings | GhidraSnippets | Same, plus hand-walking varnode definitions |
| Count all mnemonics | GhidraSnippets | Clean |
| Basic block details | GhidraSnippets | `block.name` was `nil` — the module documented a member it never registered |
| Program slices | GhidraSnippets | Raw `DecompilerUtils` |
| Emulating a function | GhidraSnippets | Raw `EmulatorHelper`; still is |

A second round, chosen from the survey above rather than by hand:

| Script | Origin | Outcome |
|---|---|---|
| `CallAnotherScriptForAllPrograms.java` | Ghidra | Every line was raw Java: project, folders, files, borrow/release, `runScript` |
| `BatchRename.java` | Ghidra | Same, plus `askProjectFolder` |
| `AskValuesExampleScript.java` | Ghidra | `GhidraValuesMap` built field by field, validator through `java.proxy` |
| `IterateFunctionsByAddressScript.java` | Ghidra | `getFunctionBefore` is on the flat API only, and nothing wrapped it |
| `HelloWorldPopupScript.java` | Ghidra | One line, and it had no equivalent |
| `ExampleColorScript.java` | Ghidra | Raw `ColorizingService`; GUI-only, not run |
| `FindSharedReturnFunctionsScript.java` (table half) | Ghidra | Two Java interfaces by hand; GUI-only, not run |

## What changed

### P-code stopped being raw Java

No P-code class had any Luau members: `PcodeOp`, `Varnode`, `HighVariable`,
`HighSymbol`, `CodeBlock`, and `CodeBlockReference` all fell through to the Java
API. Worse, `@ghidra/pcode` and `@ghidra/blocks` both *documented* members that
were never registered — `op.mnemonic`, `block.name` — so the first thing either
example did was return nil.

They are registered now, and the two doc comments are true again.

On top of them, the pattern every third advanced script needs: what was passed to
this call. Before, from the GhidraSnippets recipe as ported:

```lua
for op in pcode.ops(caller) do
    if op:getMnemonic() ~= "CALL" then continue end
    local inputs = op:getInputs()
    if #inputs <= 3 then continue end          -- a Java array raises past its end
    if tostring(inputs[1]:getAddress()) ~= tostring(target.entry) then continue end
    local nameOffset = constantOf(inputs[3])   -- 20 lines of definition walking
    ...
```

After:

```lua
for call in pcode.callsTo("register_function") do
    local name = pcode.stringOf(call.args[2])
    local handler = ghidra.functionAt(pcode.addressOf(call.args[3]))
    if name and handler then handler:rename(name) end
end
```

That is the whole "rename handlers after the string they registered with" recipe.
It renamed all three handlers in the test binary.

`pcode.constant` follows the copies, casts, and `PTRSUB` sums the decompiler puts
between a call and its constant, which is what the hand-written versions were all
approximating. `pcode.stringOf` refuses non-printable bytes, so a function pointer
does not come back as a one-character string — an actual bug in the naive version.

Slices came along too: `pcode.forwardSlice`, `backwardSlice`, and their
`...Ops` variants, over the same `DecompilerUtils` the recipe reaches for.

### Java arrays iterate

`for _, input in op:getInputs() do` raised "attempt to iterate over a userdata
value". Ghidra's array-returning API is everywhere — a p-code op's inputs, an
instruction's result objects, `getPcode()` — and every port that touched one had
to fall back to a numeric loop. Arrays now have `__iter` in the native bridge, so they
iterate like a Luau array. `#arr` and `arr[i]` are unchanged.

### `reference.isData`

`Reference` had `isCall`, `isJump`, `isRead`, and `isWrite`, but Ghidra marks the
reference from a call site to a string argument as `PARAM`, so the port of
`RecursiveStringFinder.py` silently found nothing until it used the Java
`refType:isData()`. `isData`, `isFlow`, and `isIndirect` are properties now.

### Running other programs

Three of the four ghidraninja scripts read here shell out — to `yara`, to
`binwalk`, to a Swift demangler — and Luau has no `os.execute` or `io.popen`. The port had to
drive `ProcessBuilder` by hand, about fifteen lines before it could read a line of
output. `@ghidra/process` covers it:

```lua
for line in process.lines({ "nm", "-U", ghidra.program().executablePath }) do end
process.run({ "binwalk", "-c", path })    -- { ok, code, stdout, stderr }
process.which("yara")
```

A command is an array and never reaches a shell. `run` reports failure in its
result because tools routinely exit non-zero to mean "nothing found"; `output` and
`lines` raise instead.

### File offsets

`yara.py` converts a physical file offset to an address by walking
`block.getSourceInfos()[0].fileBytesOffset` by hand, and a whole bundled script
exists for the same conversion. Both directions are one call now:
`memory.fileOffset(addr)`, `memory.fileName(addr)`,
`memory.addressesForFileOffset(offset)`.

### Analyzer options

`GetAndSetAnalysisOptionsScript.java` is entirely `GhidraScript` helpers that have
no Luau equivalent, so the port went straight to `program:getOptions("Analyzers")`.
`analysis.options()`, `analysis.option(name)`, `analysis.setOption(name, value)`,
and `analysis.resetOptions(names?)` cover it. This one came up for real: the
harness for this study needed to turn off an analyzer before importing anything.

### The project, and the script object behind it

Nothing in `@ghidra` reached the project, so the whole batch-processing family of
bundled scripts — open every program under a folder, do something, save — was raw
Java: `state.getProject()`, `ProjectData`, `DomainFolder`, `DomainFile`, content
types, checkout state, and the borrow/release protocol that leaks a program if a
script raises in the middle.

`ghidra.script()` is the missing escape hatch, `ghidra.runScript` runs another
script, and `@ghidra/project` is the walk:

```lua
for program, file in project.programs() do
    print(file:getPathname(), program.functionCount)
end
```

Each program is opened, handed to the body, and released before the loop moves
on — including when the body raises. Versioned files nobody has checked out are
skipped. Run against a two-program project, that replaced 60 lines of the
`CallAnotherScriptForAllPrograms.java` port with three.

`ui.askProjectFolder`, `ui.askProgram`, `ui.askDomainFile`, and `ui.askLanguage`
round out the prompts, and `ui.popup` prints instead of blocking when there is no
GUI.

### One dialog for several values

`askValues` is Ghidra's answer to a script asking six questions in a row, and
thirteen bundled scripts use it. The port had to build a `GhidraValuesMap` field
by field and implement the validator interface through `java.proxy`.
`ui.askValues` takes a Luau array of fields and gives back a table:

```lua
local answers = ui.askValues("Report options", {
    { name = "Name", kind = "string" },
    { name = "Max Results", kind = "int", default = 100 },
    { name = "Priority", kind = "choice", choices = { "Low", "High" } },
})
```

### Walking outwards from an address

`ghidra.functionAt` answers only at an exact entry point, and there was nothing
for "the next function", "the data before this", or "the instruction covering
this address" — all of which live on the flat API, which the `FunctionManager`
does not have, so the port of `IterateFunctionsByAddressScript.java` failed twice
before finding them. Added: `functionAfter`/`functionBefore`,
`firstFunction`/`lastFunction`, `instructionAfter`/`instructionBefore`,
`dataAfter`/`dataBefore`, the three `...Containing` lookups, and
`referencedAddress`.

### Smaller things

- `func:complexity()` — cyclomatic complexity, the whole content of one bundled
  script.
- `func:calls()` and `func:callSites()`, the two `@ghidra/pcode` iterators from
  the function's own side.
- `ui.askBytes`, which `XorMemoryScript.java` and `AskScript.java` both use.
- `io` paths accept the `java.io.File` that `ui.askFile` returns.
- `references.add` takes a source type, so a script can add `ANALYSIS`
  references the way `mark_in_out.py` does rather than only `USER_DEFINED` ones.
- `ghidra_scripts/LuauCallArguments.luau`, a shipped example that prints every
  call in a program with its arguments resolved to strings and constants.

## Still open

Ordered by how often the corpus wanted them.

**An emulator module.** `EmulatorHelper` is a headline Ghidra feature and the
GhidraSnippets recipe for it is long. A port has to do all of it by hand: build
the helper, write registers by name, set a fake return address, step, and read
memory back. Something like `emulator.of(func)` with `run{ until = addr }`,
register and memory accessors, and a step callback would turn thirty lines into
five. This is the largest remaining hole.

**Instruction operand structure.** `RegisterTouchesPerFunction.java` wants the
objects behind an operand — is this a register, a scalar, an address — and its
port fell back to `getResultObjects` and `getInputObjects`, plus a Java class test
to tell a register from anything else. `mark_in_out.py`, read but not ported,
needs the same thing through `getOperandType` bit masks. `instruction:inputs()`,
`instruction:results()`, `instruction:operandObjects(n)`, and predicates for the
operand kinds would cover a whole family of scripts. `instruction.fallFrom` and
`instruction:next()`/`previous()` belong here too; `mark_in_out.py` walks
backwards from an `IN`/`OUT` instruction to find the register load.

**A results table.** Ten bundled scripts show their findings in a
`TableChooserDialog` — a navigable list with a column set and an action button —
rather than printing them. A Luau script can build one, but only by implementing
`TableChooserExecutor` and `StringColumnDisplay` through `java.proxy` and
constructing row objects Ghidra recognizes. `ui.table{ columns = ..., onExecute =
... }` would make "show me the hits" as cheap as printing them. It needs a GUI to
test, which is why it is a proposal here rather than an addition.

**Colouring the listing, and the graph service.** `ExampleColorScript.java` and
`ExampleGraphServiceScript.java` are both small, both GUI-only, and both entirely
raw Java in a port. `ui.setBackgroundColor(target, colour)` and a thin graph
builder would cover them.

**Symbol filtering by kind.** Both 0xdea scripts open with the same loop: iterate
every symbol, keep the ones where `getSymbolType() == SymbolType.FUNCTION` and
`isExternal()` is false. `ghidra.symbols({ kind = "FUNCTION", external = false })`
would say it directly.

**`ghidra.functions({ external = true })` reads as "include external".** It means
"external only", and the Rhabdomancer port quietly found nothing because of it —
the names all matched, but the call sites live on the thunks in the listing, which
that iterator skips. Either rename it or add `includeExternal`.

**Undecorated name lookup.** The same port had to strip `_` prefixes and
`@GLIBC_2.4` suffixes itself to match a list of libc names against a Mach-O or an
ELF; the original Java carries a TODO about exactly this. `ghidra.functionsNamed`
could take `{ undecorated = true }`.

**`data.representation` and `data.isString`.** `CountAndSaveStrings.java` and
`RecursiveStringFinder.py` both test "is this string-ish" by lowercasing the type
name and looking for `"string"` or `"unicode"`, then read
`getDefaultValueRepresentation()`. Both deserve to be properties.

**Iterating a Java `Iterable` directly.** `ghidra.iterate(list)` works, but now
that arrays iterate, `for value in list do` is the obvious next expectation.

**Automatic comments.** `DisplayableEol` — the grey comments Ghidra generates —
has no wrapper; one GhidraSnippets recipe is about nothing else.

## Reproducing

The ports are not part of the repository; they were written and run in a scratch
directory. What is committed is what came out of the exercise: the API additions,
their tests in `src/test/luau`, and `ghidra_scripts/LuauCallArguments.luau`.

`gradle luaTest` covers the new surface against the in-memory scratch program.
Running the ports themselves needs a real binary and the headless invocation shown
above; the project ports also need a project with more than one program in it,
which is just a second `-import`.
