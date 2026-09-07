#ifndef LUAGHIDRA_LUAU_REQUIRE_H
#define LUAGHIDRA_LUAU_REQUIRE_H

#include <jni.h>

extern "C"
{
#include <lua.h>
}

// Installs the global `require` function into the given Luau state.
void luaghidra_installRequire(JNIEnv* env, lua_State* L);

// Publishes 'host' as the result of require("@host"), the object the @ghidra
// module is built on. Passing nullptr removes it.
void luaghidra_setHostModule(JNIEnv* env, lua_State* L, jobject host);

#endif // LUAGHIDRA_LUAU_REQUIRE_H
