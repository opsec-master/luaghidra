#ifndef LUAGHIDRA_JAVA_BRIDGE_H
#define LUAGHIDRA_JAVA_BRIDGE_H

#include <jni.h>

#include <string>
#include <vector>

extern "C"
{
#include <lua.h>
}

// Installs the `java` module (and its jclass/jobject userdata machinery) into
// the given Luau state. Safe to call once per state, right after luaL_openlibs.
void luaghidra_installJavaModule(JNIEnv* env, lua_State* L);

// Returns a JNIEnv for the current thread, attaching if necessary. May return
// nullptr if no JavaVM has been registered (i.e. JNI_OnLoad never ran).
JNIEnv* luaghidra_getEnv();

// Raises a Lua error carrying the pending Java exception's message, if any, and
// records it for java.caught(). Does not return when an exception is pending.
void luaghidra_checkJavaException(JNIEnv* env, lua_State* L);

// Pushes a Java object onto the Lua stack as a jclass/jobject/jarray userdata,
// or as a plain Lua value for booleans, numbers, and strings.
void luaghidra_pushJava(JNIEnv* env, lua_State* L, jobject value);

// Pushes the Luau function handling 'method' for the java.proxy handler with
// this id and returns true, or returns false having pushed nothing.
bool luaghidra_pushProxyHandler(lua_State* L, int handlerId, const char* method);

// Converts the Lua value at 'index' to a Java object (a local reference, or
// nullptr for nil).
jobject luaghidra_toJava(JNIEnv* env, lua_State* L, int index);

// Returns every member name available on the Java userdata at 'index': the
// class's public fields and methods, plus any registered Luau extension
// properties and methods. Empty when the value is not a Java userdata.
std::vector<std::string> luaghidra_memberNames(JNIEnv* env, lua_State* L, int index);

#endif // LUAGHIDRA_JAVA_BRIDGE_H
