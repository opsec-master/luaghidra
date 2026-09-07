# Reaching into Java

[LuaGhidra](../README.md) · [API](api.md) · [Modules](modules.md) · **Java** · [Scripts](scripts.md) · [Development](development.md)

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

## Implementing Java interfaces

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

