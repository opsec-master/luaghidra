# Development

[LuaGhidra](../README.md) · [API](api.md) · [Modules](modules.md) · [Java](java.md) · [Scripts](scripts.md) · **Development**

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

## Layout

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

## Native build

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

## Releases

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

## Source-tree development

This repository is expected to sit beside a Ghidra checkout. Add `LuaGhidra` to
`../ghidra/ghidra.repos.config` and run Gradle from the Ghidra source tree; the
project is included as `:LuaGhidra` and targets the same Java version.
