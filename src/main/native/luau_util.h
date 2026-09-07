#ifndef LUAGHIDRA_LUAU_UTIL_H
#define LUAGHIDRA_LUAU_UTIL_H

#include <cstddef>
#include <string>

extern "C"
{
#include <lua.h>
}

// Compiles 'source' and leaves the resulting function on the Lua stack.
// Returns LUA_OK on success; on failure the error message is left on the stack.
int luaghidra_loadSource(lua_State* L, const char* source, size_t length, const char* chunkName);

// Compiles and runs 'source' as a chunk taking no arguments, leaving 'results'
// values on the stack. Raises a Lua error on failure.
void luaghidra_runSource(lua_State* L, const char* source, const char* chunkName, int results);

// True when a load error message indicates the chunk was cut off mid-statement,
// which the console uses to switch to its continuation prompt.
bool luaghidra_isIncomplete(const std::string& message);

#endif // LUAGHIDRA_LUAU_UTIL_H
