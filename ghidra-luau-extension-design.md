# Ghidra Luau Extension Design Notes

This document distills the design discussion for a Ghidra extension that adds **Luau** as a scripting language. The goal is not just “Lua inside Ghidra,” but a **typed, editor-friendly scripting experience where Java interop is first-class** and Luau utilities make common Ghidra work pleasant.

## Core Thesis

The extension should provide one coherent object model with two layers:

1. **Typed Java proxy layer**  
   Ghidra objects are Java proxies by default. Scripts can call Java methods, require generated package modules, use Java enums, and receive Java objects without leaving the normal scripting model.

2. **Luau utility layer**  
   The `@ghidra` module provides convenience functions, iterators, properties, transaction helpers, and class-specific extension methods on top of Java proxies.

Everything else should be avoided by default: no magic globals, no implicit runtime selection, no hidden injected names, and no split between “real Java objects” and “Lua wrapper objects” that forces users to constantly convert values.

---

## Motivation

Existing Ghidra scripting ecosystems can be confusing because the same object is often accessible through several paths.

For example, Python/Jython/PyGhidra-style scripting often exposes or encourages patterns like:

```python
currentProgram
state.getCurrentProgram()
getCurrentProgram()
```

This creates uncertainty:

- Are these the same object?
- Are they wrappers or raw Java objects?
- Which API style should new scripts use?
- Which style has better editor support?
- Which style is stable across runtimes?

For the Luau extension, the answer should be simpler:

```lua
local ghidra = require("@ghidra")
```

Use `@ghidra` for normal scripting conveniences. Use package-shaped modules for Java classes, enums, and typed package APIs.

For example:

```lua
local ghidra = require("@ghidra")
local listing = require("@ghidra/program/model/listing")
local symbol = require("@ghidra/program/model/symbol")

local Function = listing.Function
local SourceType = symbol.SourceType
```

Most values returned by `@ghidra` should still be Java proxies. For example, `ghidra.program()` should return a proxy for `ghidra.program.model.listing.Program`, decorated with useful Luau additions. That means both of these should feel natural:

```lua
local program = ghidra.program()

print(program:getName()) -- Java method
print(program.name)      -- Luau convenience property
```

---

## Runtime Selection

A required `@runtime` directive is probably unnecessary if the extension owns the `.luau` file extension.

Recommended behavior:

```text
.luau files -> always Luau
.lua files  -> unsupported by default, or opt-in only
```

Optional metadata may still be supported:

```lua
-- @runtime Luau
-- @category Analysis.Luau
-- @menupath Tools.Luau.Find Suspicious Strings

--!strict
```

However, `@runtime Luau` should be optional for `.luau` files. It can be accepted as documentation or validation, but should not be required boilerplate.

### Recommended Runtime Policy

```text
.luau with no @runtime       -> runs as Luau
.luau with @runtime Luau     -> runs as Luau
.luau with @runtime LuaJIT   -> clear error
.lua with @runtime Luau      -> maybe supported only if explicitly enabled
.lua with no @runtime        -> preferably unsupported
```

### Why Prefer `.luau` Over `.lua`

Using `.luau` communicates that:

- this is Luau, not stock Lua;
- typed syntax is supported and encouraged;
- users should not expect LuaJIT, Lua 5.1, Lua 5.4, or standard Lua compatibility;
- the extension owns the runtime behavior.

Avoid silently treating all `.lua` files as Luau, because users may reasonably expect ordinary Lua semantics.

---

## No Magic Globals by Default

Avoid exposing these as default globals:

```lua
currentProgram
currentAddress
currentSelection
state
monitor
askFile
askString
println
```

Instead, use explicit module access:

```lua
local ghidra = require("@ghidra")

local program = ghidra.program()
local address = ghidra.currentAddress()
local selection = ghidra.selection()
local monitor = ghidra.monitor()

ghidra.log("Done")
```

This makes dependencies visible and improves type checking, autocomplete, and readability.

### Compatibility Mode

If compatibility with traditional Ghidra scripting patterns is desired, make it explicit and opt-in:

```lua
local compat = require("@ghidra/compat/globals")
compat.install()
```

Or via a directive:

```lua
--!compat ghidra-globals
```

But do not enable this by default.

---

## API Design Principle

Java proxies should be the primary values scripts work with.

The extension should not create a parallel wrapper hierarchy that users must unwrap for advanced work. A Ghidra object exposed to Luau should normally be the generated package type plus its registered utility extensions:

```lua
listing.Function & FunctionExt
```

That means the same value can support Java calls and Luau conveniences:

```lua
local func = ghidra.functionAt("401000")

print(func:getName()) -- native Ghidra Java API
print(func.name)      -- Luau property alias

func:setName("main", SourceType.USER_DEFINED) -- native Java method
func:rename("main")                           -- Luau utility method
```

### Dispatch and Collision Rules

The bridge should be predictable. Member lookup should follow a documented order:

1. Java methods, fields, enum constants, and explicitly selected overloads.
2. Luau extension properties and methods registered for the Java class or interface.
3. Shared Java proxy helpers, such as `:javaClassName()`, `:javaMethod(...)`, or package class-object helpers like `Function.cast(...)`.

Luau extensions must not silently shadow Java members. If a utility name would collide with a Java member, either choose another name or expose the helper through a namespace such as `ghidra.functionUtils.rename(func, "main")`.

This allows common scripts to be concise without taking away the full Java API:

```lua
local program = ghidra.program()

local listing = program:getListing()        -- Java
local fm = program:getFunctionManager()     -- Java
local funcs = program:functions()           -- Luau extension iterator
local all = ghidra.functions({ forward = true }) -- top-level utility
```

### Recommended Rule

```text
Package modules    = generated Ghidra Java classes, enums, and package types
Java proxy methods = complete Ghidra API surface
@ghidra utilities  = concise common scripting operations
```

The distinction is not “simple API versus raw escape hatch.” The distinction is “Ghidra Java object model plus Luau conveniences.”

---

## Primary User-Facing API

The normal scripting entry point should be:

```lua
local ghidra = require("@ghidra")
```

This module should return Java proxies and Java-backed iterators, not detached Luau-only wrapper objects.

Example:

```lua
--!strict

local ghidra = require("@ghidra")

local program = ghidra.program()

print(`Program: {program.name}`)
print(`Language: {program:getLanguageID()}`)
print(`Image base: {program.imageBase}`)

for func in ghidra.functions({ forward = true }) do
    print(`{func.name} @ {func.entry}`)
end
```

---

## Suggested Module Layout

Core modules:

```lua
local ghidra = require("@ghidra")
```

Generated Java package modules:

```lua
local listing = require("@ghidra/program/model/listing")
local address = require("@ghidra/program/model/address")
local symbol = require("@ghidra/program/model/symbol")
local decompilerApi = require("@ghidra/app/decompiler")
```

Optional focused modules:

```lua
local decompiler = require("@ghidra/decompiler")
local memory = require("@ghidra/memory")
local symbols = require("@ghidra/symbols")
local ui = require("@ghidra/ui")
```

The core `@ghidra` module should be sufficient for common scripts that only need utilities. Package modules should mirror Ghidra's Java package structure and provide the generated class, enum, and interface definitions for that package.

---

## Proxy Extension API Sketch

A generated or hand-authored type declaration might look like this:

```lua
declare module "@ghidra" {
    -- Sketch notation: listing.*, address.*, and symbol.* refer to
    -- generated package modules such as @ghidra/program/model/listing.

    export type AddressExt = {
        offset: number,
        space: string,
        tostring: (self: address.Address & AddressExt) -> string,
    }

    export type ProgramExt = {
        name: string,
        imageBase: address.Address & AddressExt,

        functions: (self: listing.Program & ProgramExt, options: FunctionQuery?) -> () -> (listing.Function & FunctionExt)?,
        functionAt: (self: listing.Program & ProgramExt, address: (address.Address & AddressExt) | string | number) -> (listing.Function & FunctionExt)?,
        transaction: <T>(self: listing.Program & ProgramExt, name: string, fn: () -> T) -> T,
    }

    export type FunctionExt = {
        name: string,
        entry: address.Address & AddressExt,
        body: AddressSetView,

        rename: (self: listing.Function & FunctionExt, name: string, sourceType: symbol.SourceType?) -> (),
        decompile: (self: listing.Function & FunctionExt, options: DecompileOptions?) -> DecompileResult,
    }

    export type DecompileResult =
        { ok: true, c: string }
        | { ok: false, error: string }

    export function program(): listing.Program & ProgramExt
    export function currentAddress(): (address.Address & AddressExt)?
    export function selection(): AddressSetView?
    export function monitor(): TaskMonitor
    export function address(value: string | number): address.Address & AddressExt
    export function functions(options: FunctionQuery?): () -> (listing.Function & FunctionExt)?
    export function functionAt(address: (address.Address & AddressExt) | string | number): (listing.Function & FunctionExt)?
    export function log(message: string): ()
    export function warn(message: string): ()
    export function checkCancelled(): ()
}
```

---

## Package-Shaped Java API

Java classes and enums should be exposed through modules that mirror Ghidra's Java package structure. There should not be a separate `java.Function` or `ghidra.Function` class namespace.

Example:

```lua
--!strict

local ghidra = require("@ghidra")
local listing = require("@ghidra/program/model/listing")

local program = ghidra.program()
local fm = program:getFunctionManager()
local funcs = fm:getFunctions(true)

while funcs:hasNext() do
    local f: listing.Function = funcs:next()
    print(f:getName())
end
```

### Requiring Java Classes

```lua
local decompilerApi = require("@ghidra/app/decompiler")

local DecompInterface = decompilerApi.DecompInterface
local ifc = DecompInterface.new()
```

Enums:

```lua
local symbol = require("@ghidra/program/model/symbol")

local SourceType = symbol.SourceType
func:setName("main", SourceType.USER_DEFINED)
```

Bridge helpers should use the class objects exported by package modules:

```lua
local listing = require("@ghidra/program/model/listing")

local Function = listing.Function

local func = Function.cast(someObject)
local className = func:javaClassName()
local overload = func:javaMethod("setName", {
    "java.lang.String",
    "ghidra.program.model.symbol.SourceType",
})
```

### Package Type Declaration Sketch

Generated package declarations should live next to the package they represent. For example, `@ghidra/program/model/listing` might expose:

```lua
declare module "@ghidra/program/model/listing" {
    -- Sketch notation: address.* and symbol.* refer to their generated
    -- package modules, not global namespaces.

    export type JavaClass<T> = {
        new: (...any) -> T,
        cast: (obj: any) -> T,
        isInstance: (obj: any) -> boolean,
    }

    export type Program = JavaProxy<"ghidra.program.model.listing.Program"> & {
        getName: (self: Program) -> string,
        getListing: (self: Program) -> Listing,
        getFunctionManager: (self: Program) -> FunctionManager,
        startTransaction: (self: Program, description: string) -> number,
        endTransaction: (self: Program, transactionId: number, commit: boolean) -> (),
    }

    export type FunctionManager = JavaProxy<"ghidra.program.model.listing.FunctionManager"> & {
        getFunctions: (self: FunctionManager, forward: boolean) -> FunctionIterator,
        getFunctionAt: (self: FunctionManager, addr: address.Address) -> Function?,
    }

    export type FunctionIterator = JavaIterator<Function>

    export type Function = JavaProxy<"ghidra.program.model.listing.Function"> & {
        getName: (self: Function) -> string,
        getEntryPoint: (self: Function) -> address.Address,
        setName: (self: Function, name: string, sourceType: symbol.SourceType) -> (),
    }

    export const Program: JavaClass<Program>
    export const Function: JavaClass<Function>
}
```

And `@ghidra/program/model/symbol` might expose:

```lua
declare module "@ghidra/program/model/symbol" {
    export type SourceType = JavaEnumValue<"ghidra.program.model.symbol.SourceType">

    export const SourceType: {
        USER_DEFINED: SourceType,
        ANALYSIS: SourceType,
        DEFAULT: SourceType,
        IMPORTED: SourceType,
    }
}
```

The exact declaration syntax can be adjusted to fit Luau tooling, but the important constraint is that package modules own class names.

---

## Java Proxy Decoration

Since script values are already Java proxies, there should not be a routine `:java()` conversion step.

Instead, the runtime should decorate selected Java classes and interfaces with Luau conveniences:

```lua
local ghidra = require("@ghidra")

local func = ghidra.functionAt("401000")

if func then
    print(func:getSignature():getPrototypeString()) -- Java
    print(func.signature)                           -- Luau convenience, if provided
end
```

Decoration should be idempotent and type-driven. If Java returns a `ghidra.program.model.listing.Function`, Luau sees the same Java proxy with `FunctionExt` utilities attached.

```lua
local ghidra = require("@ghidra")

local func = ghidra.program()
    :getFunctionManager()
    :getFunctionAt(ghidra.address("401000"))

print(func.name)
print(func:getName())
```

Possible decoration helpers:

```lua
export function decorateProgram(program: listing.Program): listing.Program & ProgramExt
export function decorateFunction(func: listing.Function): listing.Function & FunctionExt
export function decorateAddress(addr: address.Address): address.Address & AddressExt
```

These helpers should mostly exist for type narrowing or advanced bridge work. Normal scripts should not need them.

---

## Java Overloads

Java overloads are difficult to model perfectly in Luau.

For simple cases, use intersection-style function types if tooling supports them:

```lua
export type AddressFactory = {
    getAddress:
        ((self: AddressFactory, address: string) -> address.Address?)
        & ((self: AddressFactory, space: address.AddressSpace, offset: number) -> address.Address?),
}
```

If tooling struggles, collapse overloaded signatures to a less precise fallback:

```lua
export type AddressFactory = {
    -- Java overloads collapsed:
    -- getAddress(String)
    -- getAddress(AddressSpace, long)
    getAddress: (self: AddressFactory, ...any) -> address.Address?,
}
```

This is less precise, but still provides discoverability.

---

## Java Generics

Handle Java generics pragmatically.

```lua
export type JavaIterator<T> = {
    hasNext: (self: JavaIterator<T>) -> boolean,
    next: (self: JavaIterator<T>) -> T,
}

export type JavaList<T> = {
    size: (self: JavaList<T>) -> number,
    get: (self: JavaList<T>, index: number) -> T,
    iterator: (self: JavaList<T>) -> JavaIterator<T>,
}

export type FunctionIterator = JavaIterator<listing.Function>
```

The first goal should be useful autocomplete, not perfect Java type theory.

---

## Transactions

Ghidra mutations often require transactions. The Luau utility layer should make this easy and safe.

Instead of requiring Java-style transaction boilerplate, support:

```lua
--!strict

local ghidra = require("@ghidra")

local program = ghidra.program()

program:transaction("Rename tiny functions", function()
    for func in program:functions() do
        if func.body:size() < 16 then
            func:rename("tiny_" .. tostring(func.entry))
        end
    end
end)
```

Or global transaction helper:

```lua
ghidra.transaction("Rename functions", function()
    for func in ghidra.program():functions() do
        if func.name:match("^FUN_") then
            func:rename("sub_" .. tostring(func.entry))
        end
    end
end)
```

---

## Task Monitor and Cancellation

Avoid a magic `monitor` global. Provide explicit APIs:

```lua
local ghidra = require("@ghidra")

for func in ghidra.program():functions() do
    ghidra.checkCancelled()
    ghidra.status(`Scanning {func.name}`)
end
```

Or a task helper:

```lua
local task = ghidra.task("Scanning functions", {
    max = ghidra.program():functionCount(),
})

for func in ghidra.program():functions() do
    task:checkCancelled()
    task:increment()
end
```

---

## Error Handling

Common Luau utility APIs should avoid exposing raw Java exceptions when possible.

Prefer result-style return values for fallible operations:

```lua
local result = func:decompile()

if result.ok then
    print(result.c)
else
    ghidra.warn(result.error)
end
```

Potential type:

```lua
export type Result<T, E> =
    { ok: true, value: T }
    | { ok: false, error: E }
```

Direct Java calls can still behave like Java interop and throw bridge-native errors, handled with `pcall`:

```lua
local ok, err = pcall(function()
    program:someJavaMethod()
end)
```

---

## Editor and Type Support

Typing should be a first-class feature, not an afterthought.

Ship generated declaration files for:

```text
@ghidra/init.luau                    -- Luau utility and extension API
@ghidra/program/model/listing.luau   -- generated listing package API
@ghidra/program/model/symbol.luau    -- generated symbol package API
@ghidra/app/decompiler.luau          -- generated decompiler package API
```

Avoid loading every generated package by default if it makes the language server slow. Scripts should pull in package modules with `require` as needed.

Recommended tiers:

```text
Core types:
  Program, Function, Listing, Address, Symbol, Memory, DataType, Decompiler

Full types:
  every public Ghidra Java class
```

---

## Versioned Type Packs

Types should be generated per Ghidra version.

Example layout:

```text
.ghidra-luau/
  types/
    ghidra-12.0.1/
      @ghidra/
        init.luau
        program/
          model/
            listing.luau
            symbol.luau
            address.luau
        app/
          decompiler.luau
```

A diagnostic command should report mismatches:

```text
Ghidra API: 12.0.1
Generated Luau utility types: 12.0.1
Generated package types: 12.0.1
Status: matched
```

If stale:

```text
Warning: package types were generated for Ghidra 12.0.1 but running against 12.1.0.
Run: ghidra-luau generate-types
```

---

## Suggested CLI / Developer Tools

Useful commands:

```bash
ghidra-luau doctor
ghidra-luau generate-types
ghidra-luau init-vscode
ghidra-luau run sample.exe scripts/FindCrypto.luau
```

### `doctor` Output Example

```text
Ghidra version: 12.0.1
GhidraLuau extension: 0.3.0
Luau runtime: 0.x
Script provider registered: yes
Headless support: yes
Type definitions: generated for Ghidra 12.0.1
VS Code config: found
```

---

## Headless Support

Headless and CI support should be deterministic and non-interactive.

Example target usage:

```bash
analyzeHeadless /tmp/proj MyProj \
  -import sample.exe \
  -postScript script.luau \
  -scriptRuntime Luau \
  -deleteProject
```

Optional standalone runner:

```bash
ghidra-luau run sample.exe scripts/FindCrypto.luau
```

Avoid first-run prompts, hidden GUI assumptions, and per-user state requirements.

---

## Example Scripts

### Iterate Functions

```lua
--!strict

local ghidra = require("@ghidra")

for func in ghidra.program():functions() do
    print(`{func.name} @ {func.entry}`)
end
```

### Rename Functions in a Transaction

```lua
--!strict

local ghidra = require("@ghidra")

local program = ghidra.program()

program:transaction("Rename auto functions", function()
    for func in program:functions() do
        if func.name:match("^FUN_") then
            func:rename("sub_" .. tostring(func.entry))
        end
    end
end)
```

### Search Strings

```lua
--!strict

local ghidra = require("@ghidra")

for stringRef in ghidra.strings({ minLength = 6 }) do
    if stringRef.value:find("http") then
        ghidra.comment(stringRef.address, "possible URL")
    end
end
```

### Use Package Modules Directly

```lua
--!strict

local ghidra = require("@ghidra")
local decompilerApi = require("@ghidra/app/decompiler")

local DecompInterface = decompilerApi.DecompInterface
local ifc = DecompInterface.new()

ifc:openProgram(ghidra.program())

for func in ghidra.program():functions() do
    local result = ifc:decompileFunction(
        func,
        30,
        ghidra.monitor()
    )

    local decompiled = result:getDecompiledFunction()
    if decompiled ~= nil then
        print(decompiled:getC())
    end
end
```

---

## Documentation Rules

Examples should freely use Java methods on Ghidra objects when that is the clearest expression of the operation. Use `@ghidra` utilities for common scripting patterns, iteration, transactions, cancellation, logging, and concise property access.

Avoid documenting several equivalent entry points for the same state:

```lua
-- Avoid this kind of documentation mix:
print(currentProgram:getName())
print(state.getCurrentProgram():getName())
print(getCurrentProgram():getName())
```

Preferred documentation style:

```lua
local ghidra = require("@ghidra")

local program = ghidra.program()
print(program.name)
print(program:getExecutablePath())
```

When requiring package classes or enums, make it obvious:

```lua
local ghidra = require("@ghidra")
local symbol = require("@ghidra/program/model/symbol")

local SourceType = symbol.SourceType
local func = ghidra.functionAt("401000")

func:setName("main", SourceType.USER_DEFINED)
```

---

## MVP Scope

A good first version should avoid trying to add Luau conveniences for all of Ghidra. Instead, ship a polished Java proxy bridge plus a focused utility layer.

### MVP Checklist

- `.luau` ScriptProvider integration
- `.luau` files always run as Luau
- no magic globals by default
- `require("@ghidra")` core module
- generated package modules such as `require("@ghidra/program/model/listing")`
- typed Luau utility and extension declarations
- typed package declarations for common Ghidra classes
- direct Java method calls on returned Ghidra values
- explicit decoration/type-narrowing helpers
- transaction helper
- monitor/cancellation helper
- basic UI helpers
- headless support
- example scripts
- `doctor` diagnostics
- `generate-types` command
- VS Code/LSP setup helper

### Initial Luau Utility Coverage

Prioritize:

- Program
- Address
- Function
- Listing
- Memory
- Symbol table
- References
- Strings
- Comments
- Data types
- Decompiler
- Transactions
- Task monitor
- Logging/status output
- Basic UI prompts

---

## Design Non-Goals

For the initial design, avoid:

- supporting multiple Lua runtimes;
- supporting LuaJIT and Luau side by side;
- treating `.lua` as Luau by default;
- magic globals by default;
- separate wrapper objects that require routine `:java()` unwrapping;
- Luau utility methods that silently shadow Java members;
- requiring `@runtime Luau` boilerplate in every `.luau` script;
- documenting multiple equivalent ways to do the same task.

---

## Final Design Summary

The extension should feel like this:

```lua
--!strict

local ghidra = require("@ghidra")

for func in ghidra.program():functions() do
    print(`{func.name} @ {func.entry}`)
end
```

And direct Java use should feel like this:

```lua
--!strict

local ghidra = require("@ghidra")

local program = ghidra.program()
print(program:getName())
print(program:getFunctionManager():getFunctionCount())
```

That is the central promise:

```text
Use @ghidra for concise scripting utilities that return Java proxies.
Use package-shaped requires for Ghidra Java classes and enums.
There are no hidden globals and no wrapper/raw-object split.
```
