#include "luau_require.h"

#include "java_bridge.h"
#include "luau_util.h"

extern "C"
{
#include <lualib.h>
}

#include <string>

namespace
{
// Registry key for resolved module name -> module value.
const char* const MODULE_CACHE_KEY = "luaghidra.modules";

// Registry key for the set of modules currently being loaded, used to report
// require cycles instead of overflowing the C stack.
const char* const MODULE_LOADING_KEY = "luaghidra.loading";

struct RequireBindings
{
	bool ready = false;
	jclass modules = nullptr;
	jmethodID resolve = nullptr;
};

RequireBindings g_require;

bool initRequire(JNIEnv* env)
{
	if (g_require.ready)
	{
		return true;
	}
	jclass local = env->FindClass("luaghidra/runtime/LuaModules");
	if (local == nullptr)
	{
		env->ExceptionClear();
		return false;
	}
	g_require.modules = static_cast<jclass>(env->NewGlobalRef(local));
	env->DeleteLocalRef(local);
	g_require.resolve = env->GetStaticMethodID(g_require.modules, "resolve",
		"(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;");
	g_require.ready = g_require.resolve != nullptr;
	return g_require.ready;
}

std::string javaString(JNIEnv* env, jstring value)
{
	if (value == nullptr)
	{
		return std::string();
	}
	const char* text = env->GetStringUTFChars(value, nullptr);
	std::string result = text != nullptr ? std::string(text) : std::string();
	if (text != nullptr)
	{
		env->ReleaseStringUTFChars(value, text);
	}
	return result;
}

// Returns the chunk name of the function that called require, with Luau's
// leading '=' or '@' source marker stripped, so that relative requires resolve
// against the requiring script's directory.
std::string callerChunk(lua_State* L)
{
	lua_Debug ar;
	if (lua_getinfo(L, 1, "s", &ar) == 0 || ar.source == nullptr)
	{
		return std::string();
	}
	std::string source(ar.source);
	if (!source.empty() && (source[0] == '=' || source[0] == '@'))
	{
		source.erase(0, 1);
	}
	return source;
}

// Built-in alias modules keep their '@name' form in error messages; file
// modules are reported by path.
std::string chunkNameFor(const std::string& resolved)
{
	return (!resolved.empty() && resolved[0] == '@' ? "=" : "@") + resolved;
}

int luaRequire(lua_State* L)
{
	const char* request = luaL_checkstring(L, 1);

	JNIEnv* env = luaghidra_getEnv();
	if (env == nullptr || !initRequire(env))
	{
		luaL_error(L, "require is unavailable: the module loader could not be initialized");
	}

	// Alias modules are cached under the request string itself, so an alias that
	// was published directly (require("@host")) is found without asking the
	// resolver, which would report it missing.
	if (request[0] == '@')
	{
		lua_getfield(L, LUA_REGISTRYINDEX, MODULE_CACHE_KEY);
		lua_getfield(L, -1, request);
		if (!lua_isnil(L, -1))
		{
			return 1;
		}
		lua_pop(L, 2);
	}

	std::string from = callerChunk(L);
	jstring jfrom = from.empty() ? nullptr : env->NewStringUTF(from.c_str());
	jstring jrequest = env->NewStringUTF(request);
	jobjectArray resolved = static_cast<jobjectArray>(
		env->CallStaticObjectMethod(g_require.modules, g_require.resolve, jfrom, jrequest));
	if (jfrom != nullptr)
	{
		env->DeleteLocalRef(jfrom);
	}
	env->DeleteLocalRef(jrequest);
	luaghidra_checkJavaException(env, L);

	if (resolved == nullptr)
	{
		luaL_error(L, "module not found: %s", request);
	}

	jstring jname = static_cast<jstring>(env->GetObjectArrayElement(resolved, 0));
	jstring jsource = static_cast<jstring>(env->GetObjectArrayElement(resolved, 1));
	std::string name = javaString(env, jname);
	std::string source = javaString(env, jsource);
	env->DeleteLocalRef(jname);
	env->DeleteLocalRef(jsource);
	env->DeleteLocalRef(resolved);

	lua_getfield(L, LUA_REGISTRYINDEX, MODULE_CACHE_KEY);
	lua_getfield(L, -1, name.c_str());
	if (!lua_isnil(L, -1))
	{
		return 1;
	}
	lua_pop(L, 1);

	lua_getfield(L, LUA_REGISTRYINDEX, MODULE_LOADING_KEY);
	lua_getfield(L, -1, name.c_str());
	if (lua_toboolean(L, -1))
	{
		luaL_error(L, "require cycle detected while loading %s", name.c_str());
	}
	lua_pop(L, 1);
	lua_pushboolean(L, 1);
	lua_setfield(L, -2, name.c_str());

	std::string chunkName = chunkNameFor(name);
	if (luaghidra_loadSource(L, source.c_str(), source.size(), chunkName.c_str()) != LUA_OK)
	{
		std::string message = lua_tostring(L, -1) != nullptr ? lua_tostring(L, -1) : "syntax error";
		lua_pushnil(L);
		lua_setfield(L, -3, name.c_str());
		luaL_error(L, "%s", message.c_str());
	}

	// Run under pcall so the loading flag is cleared even when the module raises;
	// leaving it set would make a later retry look like a require cycle.
	int status = lua_pcall(L, 0, 1, 0);
	lua_pushnil(L);
	lua_setfield(L, -3, name.c_str());
	if (status != LUA_OK)
	{
		lua_error(L);
	}
	if (lua_isnil(L, -1))
	{
		luaL_error(L, "module %s did not return a value", name.c_str());
	}

	// stack: cache, loading, value
	lua_pushvalue(L, -1);
	lua_setfield(L, -4, name.c_str());
	return 1;
}
}

void luaghidra_setHostModule(JNIEnv* env, lua_State* L, jobject host)
{
	lua_getfield(L, LUA_REGISTRYINDEX, MODULE_CACHE_KEY);
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 1);
		return;
	}
	if (host == nullptr)
	{
		lua_pushnil(L);
	}
	else
	{
		luaghidra_pushJava(env, L, host);
	}
	lua_setfield(L, -2, "@host");
	lua_pop(L, 1);
}

void luaghidra_installRequire(JNIEnv* env, lua_State* L)
{
	initRequire(env);

	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, MODULE_CACHE_KEY);
	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, MODULE_LOADING_KEY);

	lua_pushcfunction(L, luaRequire, "require");
	lua_setglobal(L, "require");
}
