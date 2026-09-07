#include "java_bridge.h"

#include "luau_util.h"

extern "C"
{
#include <lualib.h>
}

#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace
{
// Userdata tags distinguishing Java references on the Luau stack.
constexpr int TAG_CLASS = 1;
constexpr int TAG_OBJECT = 2;
constexpr int TAG_ARRAY = 3;

// Registry keys for the shared metatables.
const char* const META_CLASS_KEY = "luaghidra.jclass";
const char* const META_OBJECT_KEY = "luaghidra.jobject";
const char* const META_ARRAY_KEY = "luaghidra.jarray";

// Registry key for the most recently captured Java Throwable (java.caught).
const char* const CAUGHT_KEY = "luaghidra.caught";

// Registry key for the extension registry: Java class name -> { properties, methods }
// as registered through java.extend.
const char* const EXT_KEY = "luaghidra.ext";

// Registry key for the merged-extension cache: runtime class name -> merged
// { properties, methods } table, or `false` when the class has no extensions.
const char* const EXT_CACHE_KEY = "luaghidra.extcache";

// Registry key for the Luau helper that merges a class chain's extension tables.
const char* const EXT_MERGE_KEY = "luaghidra.extmerge";

// Registry key for the light userdata identifying this interpreter state, and
// for the table of live java.proxy handlers keyed by id.
const char* const STATE_KEY = "luaghidra.state";
const char* const PROXY_KEY = "luaghidra.proxies";

// Lua type codes returned by JavaBridge.luaType (kept in sync with the Java side).
constexpr int CODE_NULL = 0;
constexpr int CODE_BOOLEAN = 1;
constexpr int CODE_LONG = 2;
constexpr int CODE_DOUBLE = 3;
constexpr int CODE_STRING = 4;
constexpr int CODE_CLASS = 5;
constexpr int CODE_ARRAY = 6;
constexpr int CODE_OBJECT = 7;

JavaVM* g_vm = nullptr;

struct Bindings
{
	bool ready = false;
	jclass bridge = nullptr;
	jclass objectClass = nullptr;
	jclass proxy = nullptr;
	jobject notFound = nullptr;
	jobject voidValue = nullptr;
	jobject methodValue = nullptr;

	jmethodID importClass = nullptr;
	jmethodID importInner = nullptr;
	jmethodID getStaticField = nullptr;
	jmethodID setStaticField = nullptr;
	jmethodID getField = nullptr;
	jmethodID setField = nullptr;
	jmethodID invokeMethod = nullptr;
	jmethodID construct = nullptr;
	jmethodID newArray = nullptr;
	jmethodID arrayGet = nullptr;
	jmethodID arraySet = nullptr;
	jmethodID arrayLength = nullptr;
	jmethodID trySetField = nullptr;
	jmethodID getMember = nullptr;
	jmethodID getStaticMember = nullptr;
	jmethodID hasMethod = nullptr;
	jmethodID hasMember = nullptr;
	jmethodID className = nullptr;
	jmethodID declaredClassName = nullptr;
	jmethodID memberNames = nullptr;
	jmethodID typeNames = nullptr;
	jmethodID luaType = nullptr;
	jmethodID asBoolean = nullptr;
	jmethodID asLong = nullptr;
	jmethodID asDouble = nullptr;
	jmethodID asString = nullptr;
	jmethodID display = nullptr;
	jmethodID valuesEqual = nullptr;
	jmethodID compare = nullptr;
	jmethodID boxLong = nullptr;
	jmethodID boxDouble = nullptr;
	jmethodID boxBoolean = nullptr;
	jmethodID newProxy = nullptr;
};

Bindings g_bindings;

bool initBindings(JNIEnv* env)
{
	if (g_bindings.ready)
	{
		return true;
	}

	jclass local = env->FindClass("luaghidra/bridge/JavaBridge");
	if (local == nullptr)
	{
		return false;
	}
	g_bindings.bridge = static_cast<jclass>(env->NewGlobalRef(local));
	env->DeleteLocalRef(local);

	jclass proxyLocal = env->FindClass("luaghidra/bridge/LuaProxy");
	if (proxyLocal != nullptr)
	{
		g_bindings.proxy = static_cast<jclass>(env->NewGlobalRef(proxyLocal));
		env->DeleteLocalRef(proxyLocal);
		g_bindings.newProxy = env->GetStaticMethodID(g_bindings.proxy, "create",
			"([Ljava/lang/String;JJ)Ljava/lang/Object;");
	}
	else
	{
		env->ExceptionClear();
	}

	jclass objLocal = env->FindClass("java/lang/Object");
	g_bindings.objectClass = static_cast<jclass>(env->NewGlobalRef(objLocal));
	env->DeleteLocalRef(objLocal);

	jclass b = g_bindings.bridge;
	g_bindings.importClass =
		env->GetStaticMethodID(b, "importClass", "(Ljava/lang/String;)Ljava/lang/Object;");
	g_bindings.importInner = env->GetStaticMethodID(b, "importInner",
		"(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;");
	g_bindings.getStaticField = env->GetStaticMethodID(b, "getStaticField",
		"(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;");
	g_bindings.setStaticField = env->GetStaticMethodID(b, "setStaticField",
		"(Ljava/lang/Object;Ljava/lang/String;Ljava/lang/Object;)V");
	g_bindings.getField = env->GetStaticMethodID(b, "getField",
		"(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;");
	g_bindings.setField = env->GetStaticMethodID(b, "setField",
		"(Ljava/lang/Object;Ljava/lang/String;Ljava/lang/Object;)V");
	g_bindings.invokeMethod = env->GetStaticMethodID(b, "invokeMethod",
		"(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/Object;");
	g_bindings.construct = env->GetStaticMethodID(b, "construct",
		"(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;");
	g_bindings.newArray =
		env->GetStaticMethodID(b, "newArray", "(Ljava/lang/Object;I)Ljava/lang/Object;");
	g_bindings.arrayGet =
		env->GetStaticMethodID(b, "arrayGet", "(Ljava/lang/Object;I)Ljava/lang/Object;");
	g_bindings.arraySet =
		env->GetStaticMethodID(b, "arraySet", "(Ljava/lang/Object;ILjava/lang/Object;)V");
	g_bindings.arrayLength = env->GetStaticMethodID(b, "arrayLength", "(Ljava/lang/Object;)I");
	g_bindings.trySetField = env->GetStaticMethodID(b, "trySetField",
		"(Ljava/lang/Object;Ljava/lang/String;Ljava/lang/Object;)Z");
	g_bindings.getMember = env->GetStaticMethodID(b, "getMember",
		"(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;");
	g_bindings.getStaticMember = env->GetStaticMethodID(b, "getStaticMember",
		"(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;");
	g_bindings.hasMethod =
		env->GetStaticMethodID(b, "hasMethod", "(Ljava/lang/Object;Ljava/lang/String;)Z");
	g_bindings.hasMember =
		env->GetStaticMethodID(b, "hasMember", "(Ljava/lang/String;Ljava/lang/String;)Z");
	g_bindings.className =
		env->GetStaticMethodID(b, "className", "(Ljava/lang/Object;)Ljava/lang/String;");
	g_bindings.declaredClassName = env->GetStaticMethodID(b, "declaredClassName",
		"(Ljava/lang/Object;)Ljava/lang/String;");
	g_bindings.memberNames =
		env->GetStaticMethodID(b, "memberNames", "(Ljava/lang/String;)[Ljava/lang/String;");
	g_bindings.typeNames =
		env->GetStaticMethodID(b, "typeNames", "(Ljava/lang/String;)[Ljava/lang/String;");
	g_bindings.luaType = env->GetStaticMethodID(b, "luaType", "(Ljava/lang/Object;)I");
	g_bindings.asBoolean = env->GetStaticMethodID(b, "asBoolean", "(Ljava/lang/Object;)Z");
	g_bindings.asLong = env->GetStaticMethodID(b, "asLong", "(Ljava/lang/Object;)J");
	g_bindings.asDouble = env->GetStaticMethodID(b, "asDouble", "(Ljava/lang/Object;)D");
	g_bindings.asString =
		env->GetStaticMethodID(b, "asString", "(Ljava/lang/Object;)Ljava/lang/String;");
	g_bindings.display =
		env->GetStaticMethodID(b, "display", "(Ljava/lang/Object;)Ljava/lang/String;");
	g_bindings.valuesEqual = env->GetStaticMethodID(b, "valuesEqual",
		"(Ljava/lang/Object;Ljava/lang/Object;)Z");
	g_bindings.compare =
		env->GetStaticMethodID(b, "compare", "(Ljava/lang/Object;Ljava/lang/Object;)I");
	g_bindings.boxLong = env->GetStaticMethodID(b, "box", "(J)Ljava/lang/Object;");
	g_bindings.boxDouble = env->GetStaticMethodID(b, "box", "(D)Ljava/lang/Object;");
	g_bindings.boxBoolean = env->GetStaticMethodID(b, "box", "(Z)Ljava/lang/Object;");

	jmethodID notFoundId =
		env->GetStaticMethodID(b, "sentinelNotFound", "()Ljava/lang/Object;");
	jmethodID voidId = env->GetStaticMethodID(b, "sentinelVoid", "()Ljava/lang/Object;");
	jmethodID methodId = env->GetStaticMethodID(b, "sentinelMethod", "()Ljava/lang/Object;");
	jobject nf = env->CallStaticObjectMethod(b, notFoundId);
	jobject vd = env->CallStaticObjectMethod(b, voidId);
	jobject mv = env->CallStaticObjectMethod(b, methodId);
	g_bindings.notFound = env->NewGlobalRef(nf);
	g_bindings.voidValue = env->NewGlobalRef(vd);
	g_bindings.methodValue = env->NewGlobalRef(mv);
	env->DeleteLocalRef(nf);
	env->DeleteLocalRef(vd);
	env->DeleteLocalRef(mv);

	g_bindings.ready = true;
	return true;
}

void pushObject(JNIEnv* env, lua_State* L, jobject local);
bool pushExtensions(JNIEnv* env, lua_State* L, jobject obj);
bool extLookup(lua_State* L, const char* section, const char* key);
std::string runtimeClassName(JNIEnv* env, jobject obj);

// Raises a Lua error if a Java exception is pending. Never returns in that case.
void checkJavaException(JNIEnv* env, lua_State* L)
{
	jthrowable e = env->ExceptionOccurred();
	if (e == nullptr)
	{
		return;
	}
	env->ExceptionClear();

	// Stash the throwable so scripts can inspect it via java.caught().
	pushObject(env, L, e);
	lua_setfield(L, LUA_REGISTRYINDEX, CAUGHT_KEY);

	jstring message =
		static_cast<jstring>(env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.display, e));
	if (env->ExceptionCheck())
	{
		env->ExceptionClear();
		message = nullptr;
	}
	if (message != nullptr)
	{
		const char* text = env->GetStringUTFChars(message, nullptr);
		lua_pushstring(L, text != nullptr ? text : "java error");
		if (text != nullptr)
		{
			env->ReleaseStringUTFChars(message, text);
		}
		env->DeleteLocalRef(message);
	}
	else
	{
		lua_pushstring(L, "java error");
	}
	env->DeleteLocalRef(e);
	lua_error(L);
}

jobject userdataRef(lua_State* L, int index)
{
	int tag = lua_userdatatag(L, index);
	if (tag != TAG_CLASS && tag != TAG_OBJECT && tag != TAG_ARRAY)
	{
		return nullptr;
	}
	void* p = lua_touserdatatagged(L, index, tag);
	return p != nullptr ? *static_cast<jobject*>(p) : nullptr;
}

void pushWrapped(JNIEnv* env, lua_State* L, jobject local, int tag, const char* metaKey)
{
	jobject global = env->NewGlobalRef(local);
	jobject* ud = static_cast<jobject*>(lua_newuserdatatagged(L, sizeof(jobject), tag));
	*ud = global;
	lua_getfield(L, LUA_REGISTRYINDEX, metaKey);
	lua_setmetatable(L, -2);
}

void pushClass(JNIEnv* env, lua_State* L, jobject local)
{
	pushWrapped(env, L, local, TAG_CLASS, META_CLASS_KEY);
}

void pushObject(JNIEnv* env, lua_State* L, jobject local)
{
	pushWrapped(env, L, local, TAG_OBJECT, META_OBJECT_KEY);
}

void pushArray(JNIEnv* env, lua_State* L, jobject local)
{
	pushWrapped(env, L, local, TAG_ARRAY, META_ARRAY_KEY);
}

// Converts a Java result object to a Lua value. Does not consume 'result'.
void pushJava(JNIEnv* env, lua_State* L, jobject result)
{
	if (result == nullptr)
	{
		lua_pushnil(L);
		return;
	}
	int code = env->CallStaticIntMethod(g_bindings.bridge, g_bindings.luaType, result);
	switch (code)
	{
	case CODE_NULL:
		lua_pushnil(L);
		break;
	case CODE_BOOLEAN:
		lua_pushboolean(L,
			env->CallStaticBooleanMethod(g_bindings.bridge, g_bindings.asBoolean, result));
		break;
	case CODE_LONG:
		lua_pushnumber(L,
			static_cast<double>(env->CallStaticLongMethod(g_bindings.bridge, g_bindings.asLong,
				result)));
		break;
	case CODE_DOUBLE:
		lua_pushnumber(L, env->CallStaticDoubleMethod(g_bindings.bridge, g_bindings.asDouble,
			result));
		break;
	case CODE_STRING:
	{
		jstring s = static_cast<jstring>(
			env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.asString, result));
		if (s != nullptr)
		{
			const char* text = env->GetStringUTFChars(s, nullptr);
			lua_pushstring(L, text != nullptr ? text : "");
			if (text != nullptr)
			{
				env->ReleaseStringUTFChars(s, text);
			}
			env->DeleteLocalRef(s);
		}
		else
		{
			lua_pushnil(L);
		}
		break;
	}
	case CODE_CLASS:
		pushClass(env, L, result);
		break;
	case CODE_ARRAY:
		pushArray(env, L, result);
		break;
	case CODE_OBJECT:
	default:
		pushObject(env, L, result);
		break;
	}
}

// Converts a single Lua value to a Java object (local ref, or nullptr for nil).
jobject luaToJava(JNIEnv* env, lua_State* L, int index)
{
	switch (lua_type(L, index))
	{
	case LUA_TNIL:
	case LUA_TNONE:
		return nullptr;
	case LUA_TBOOLEAN:
		return env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.boxBoolean,
			static_cast<jboolean>(lua_toboolean(L, index)));
	case LUA_TNUMBER:
	{
		double value = lua_tonumber(L, index);
		if (std::isfinite(value) && value == std::floor(value)
			&& value >= -9.007199254740992e15 && value <= 9.007199254740992e15)
		{
			return env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.boxLong,
				static_cast<jlong>(value));
		}
		return env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.boxDouble,
			static_cast<jdouble>(value));
	}
	case LUA_TSTRING:
		return env->NewStringUTF(lua_tostring(L, index));
	case LUA_TUSERDATA:
	{
		jobject ref = userdataRef(L, index);
		if (ref != nullptr)
		{
			return env->NewLocalRef(ref);
		}
		luaL_error(L, "cannot pass this userdata to Java");
		return nullptr;
	}
	default:
		luaL_error(L, "cannot pass %s to Java", luaL_typename(L, index));
		return nullptr;
	}
}

// Builds a Java Object[] from Lua stack positions [from, to].
jobjectArray collectArgs(JNIEnv* env, lua_State* L, int from, int to)
{
	int count = to >= from ? to - from + 1 : 0;
	jobjectArray array = env->NewObjectArray(count, g_bindings.objectClass, nullptr);
	for (int i = 0; i < count; ++i)
	{
		jobject value = luaToJava(env, L, from + i);
		env->SetObjectArrayElement(array, i, value);
		if (value != nullptr)
		{
			env->DeleteLocalRef(value);
		}
	}
	return array;
}

void completeCall(JNIEnv* env, lua_State* L, jobject result, int* pushed)
{
	if (env->IsSameObject(result, g_bindings.voidValue))
	{
		*pushed = 0;
	}
	else
	{
		pushJava(env, L, result);
		*pushed = 1;
	}
}

// Closure invoked for `obj.method` / `clazz.method` access (the non-namecall path).
// Upvalues: (1) target userdata, (2) method name, (3) boolean isStatic.
int boundCall(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	env->EnsureLocalCapacity(32);

	jobject target = userdataRef(L, lua_upvalueindex(1));
	const char* name = lua_tostring(L, lua_upvalueindex(2));
	bool isStatic = lua_toboolean(L, lua_upvalueindex(3)) != 0;

	int top = lua_gettop(L);
	int start = 1;
	if (top >= 1 && lua_isuserdata(L, 1))
	{
		jobject first = userdataRef(L, 1);
		if (first != nullptr && env->IsSameObject(first, target))
		{
			start = 2;
		}
	}

	jstring jname = env->NewStringUTF(name);
	jobjectArray args = collectArgs(env, L, start, top);
	jobject result;
	if (isStatic)
	{
		result = env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.invokeMethod, nullptr,
			target, jname, args);
	}
	else
	{
		result = env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.invokeMethod, target,
			nullptr, jname, args);
	}
	checkJavaException(env, L);

	int pushed = 0;
	completeCall(env, L, result, &pushed);
	return pushed;
}

void pushBoundCall(lua_State* L, int udIndex, const char* name, bool isStatic)
{
	lua_pushvalue(L, udIndex);
	lua_pushstring(L, name);
	lua_pushboolean(L, isStatic);
	lua_pushcclosurek(L, boundCall, "javaMethod", 3, nullptr);
}

int namecall(lua_State* L, bool isStatic)
{
	JNIEnv* env = luaghidra_getEnv();
	env->EnsureLocalCapacity(32);

	int atom = 0;
	const char* name = lua_namecallatom(L, &atom);
	if (name == nullptr)
	{
		luaL_error(L, "missing method name");
	}

	jobject target = userdataRef(L, 1);
	if (target == nullptr)
	{
		luaL_error(L, "bad self for Java method call");
	}

	int top = lua_gettop(L);
	jstring jname = env->NewStringUTF(name);
	jobjectArray args = collectArgs(env, L, 2, top);
	jobject result;
	if (isStatic)
	{
		result = env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.invokeMethod, nullptr,
			target, jname, args);
	}
	else
	{
		result = env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.invokeMethod, target,
			nullptr, jname, args);
	}
	checkJavaException(env, L);

	int pushed = 0;
	completeCall(env, L, result, &pushed);
	return pushed;
}

int jclassNamecall(lua_State* L)
{
	return namecall(L, true);
}

// Java methods take precedence; a registered extension method is used only when
// the receiver's class has no method of that name.
int jobjectNamecall(lua_State* L)
{
	const char* name = lua_namecallatom(L, nullptr);
	if (name == nullptr)
	{
		return namecall(L, false);
	}

	JNIEnv* env = luaghidra_getEnv();
	jobject target = userdataRef(L, 1);
	if (target == nullptr)
	{
		return namecall(L, false);
	}

	jstring jname = env->NewStringUTF(name);
	jboolean isJava =
		env->CallStaticBooleanMethod(g_bindings.bridge, g_bindings.hasMethod, target, jname);
	env->DeleteLocalRef(jname);
	if (isJava)
	{
		return namecall(L, false);
	}

	int top = lua_gettop(L);
	if (pushExtensions(env, L, target) && extLookup(L, "methods", name))
	{
		if (lua_isfunction(L, -1))
		{
			lua_insert(L, 1);
			lua_call(L, top, LUA_MULTRET);
			return lua_gettop(L);
		}
	}
	lua_settop(L, top);
	return namecall(L, false);
}

// Merges the extension tables registered for every type in a class's
// assignability chain into one flat lookup table. Written in Luau because the
// merge is pure table work; the native side only supplies the inputs.
const char* const EXT_MERGE_SOURCE = R"LUA(
return function(ext, typeNames)
	local properties, methods = {}, {}
	local found = false
	-- Least derived first, so a subclass extension overrides its superclass.
	for i = #typeNames, 1, -1 do
		local entry = ext[typeNames[i]]
		if entry then
			found = true
			if entry.properties then
				for key, value in entry.properties do
					properties[key] = value
				end
			end
			if entry.methods then
				for key, value in entry.methods do
					methods[key] = value
				end
			end
		end
	end
	if not found then
		return false
	end
	return { properties = properties, methods = methods }
end
)LUA";

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

std::string runtimeClassName(JNIEnv* env, jobject obj)
{
	jstring name = static_cast<jstring>(
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.className, obj));
	std::string result = javaString(env, name);
	if (name != nullptr)
	{
		env->DeleteLocalRef(name);
	}
	return result;
}

// Pushes the merged extension table for 'obj' and returns true, or returns
// false having pushed nothing. Results are cached per runtime class name.
bool pushExtensions(JNIEnv* env, lua_State* L, jobject obj)
{
	int base = lua_gettop(L);

	lua_getfield(L, LUA_REGISTRYINDEX, EXT_CACHE_KEY);
	if (!lua_istable(L, -1))
	{
		lua_settop(L, base);
		return false;
	}

	std::string name = runtimeClassName(env, obj);
	lua_getfield(L, -1, name.c_str());
	if (lua_istable(L, -1))
	{
		lua_replace(L, base + 1);
		lua_settop(L, base + 1);
		return true;
	}
	if (lua_isboolean(L, -1))
	{
		lua_settop(L, base);
		return false;
	}
	lua_pop(L, 1);

	jstring jname = env->NewStringUTF(name.c_str());
	jobjectArray types = static_cast<jobjectArray>(
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.typeNames, jname));
	env->DeleteLocalRef(jname);
	checkJavaException(env, L);

	lua_getfield(L, LUA_REGISTRYINDEX, EXT_MERGE_KEY);
	lua_getfield(L, LUA_REGISTRYINDEX, EXT_KEY);
	int count = types != nullptr ? static_cast<int>(env->GetArrayLength(types)) : 0;
	lua_createtable(L, count, 0);
	for (int i = 0; i < count; ++i)
	{
		jstring element = static_cast<jstring>(env->GetObjectArrayElement(types, i));
		std::string typeName = javaString(env, element);
		if (element != nullptr)
		{
			env->DeleteLocalRef(element);
		}
		lua_pushlstring(L, typeName.data(), typeName.size());
		lua_rawseti(L, -2, i + 1);
	}
	if (types != nullptr)
	{
		env->DeleteLocalRef(types);
	}

	lua_call(L, 2, 1);

	lua_pushvalue(L, -1);
	lua_setfield(L, base + 1, name.c_str());

	if (!lua_istable(L, -1))
	{
		lua_settop(L, base);
		return false;
	}
	lua_replace(L, base + 1);
	lua_settop(L, base + 1);
	return true;
}

// Looks up 'key' in the 'properties' or 'methods' subtable of the merged
// extension table at the top of the stack. Replaces the merged table with the
// entry and returns true, or pops it and returns false.
bool extLookup(lua_State* L, const char* section, const char* key)
{
	lua_getfield(L, -1, section);
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 2);
		return false;
	}
	lua_getfield(L, -1, key);
	if (lua_isnil(L, -1))
	{
		lua_pop(L, 3);
		return false;
	}
	lua_replace(L, -3);
	lua_pop(L, 1);
	return true;
}

int jclassIndex(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject classObj = userdataRef(L, 1);
	const char* key = lua_tostring(L, 2);
	if (key == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}

	if (std::strcmp(key, "class") == 0)
	{
		pushObject(env, L, classObj);
		return 1;
	}

	jstring jkey = env->NewStringUTF(key);

	jobject member = env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.getStaticMember,
		classObj, jkey);
	checkJavaException(env, L);
	if (env->IsSameObject(member, g_bindings.methodValue))
	{
		env->DeleteLocalRef(member);
		pushBoundCall(L, 1, key, true);
		return 1;
	}
	if (!env->IsSameObject(member, g_bindings.notFound))
	{
		pushJava(env, L, member);
		if (member != nullptr)
		{
			env->DeleteLocalRef(member);
		}
		return 1;
	}
	env->DeleteLocalRef(member);

	jobject inner =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.importInner, classObj, jkey);
	checkJavaException(env, L);
	if (!env->IsSameObject(inner, g_bindings.notFound))
	{
		pushClass(env, L, inner);
		env->DeleteLocalRef(inner);
		return 1;
	}
	env->DeleteLocalRef(inner);

	lua_pushnil(L);
	return 1;
}

int jclassNewIndex(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject classObj = userdataRef(L, 1);
	const char* key = lua_tostring(L, 2);
	if (key == nullptr)
	{
		luaL_error(L, "invalid field name");
	}
	jstring jkey = env->NewStringUTF(key);
	jobject value = luaToJava(env, L, 3);
	env->CallStaticVoidMethod(g_bindings.bridge, g_bindings.setStaticField, classObj, jkey, value);
	checkJavaException(env, L);
	return 0;
}

int jclassCall(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	env->EnsureLocalCapacity(32);
	jobject classObj = userdataRef(L, 1);
	int top = lua_gettop(L);
	jobjectArray args = collectArgs(env, L, 2, top);
	jobject result =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.construct, classObj, args);
	checkJavaException(env, L);
	pushJava(env, L, result);
	return 1;
}

// Member lookup order: Java field, Java method, then a registered Luau
// extension property or method. Extensions therefore never shadow the Java API.
int jobjectIndex(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject obj = userdataRef(L, 1);
	const char* key = lua_tostring(L, 2);
	if (key == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}

	jstring jkey = env->NewStringUTF(key);
	jobject member =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.getMember, obj, jkey);
	env->DeleteLocalRef(jkey);
	checkJavaException(env, L);

	if (env->IsSameObject(member, g_bindings.methodValue))
	{
		env->DeleteLocalRef(member);
		pushBoundCall(L, 1, key, false);
		return 1;
	}
	if (!env->IsSameObject(member, g_bindings.notFound))
	{
		pushJava(env, L, member);
		if (member != nullptr)
		{
			env->DeleteLocalRef(member);
		}
		return 1;
	}
	env->DeleteLocalRef(member);

	if (pushExtensions(env, L, obj))
	{
		lua_pushvalue(L, -1);
		if (extLookup(L, "properties", key))
		{
			lua_getfield(L, -1, "get");
			if (!lua_isfunction(L, -1))
			{
				luaL_error(L, "extension property '%s' is write-only", key);
			}
			lua_pushvalue(L, 1);
			lua_call(L, 1, 1);
			return 1;
		}
		if (extLookup(L, "methods", key))
		{
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

int jobjectNewIndex(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject obj = userdataRef(L, 1);
	const char* key = lua_tostring(L, 2);
	if (key == nullptr)
	{
		luaL_error(L, "invalid field name");
	}

	jstring jkey = env->NewStringUTF(key);
	jboolean written = env->CallStaticBooleanMethod(g_bindings.bridge, g_bindings.trySetField,
		obj, jkey, luaToJava(env, L, 3));
	env->DeleteLocalRef(jkey);
	checkJavaException(env, L);
	if (written)
	{
		return 0;
	}

	if (pushExtensions(env, L, obj))
	{
		if (extLookup(L, "properties", key))
		{
			lua_getfield(L, -1, "set");
			if (!lua_isfunction(L, -1))
			{
				luaL_error(L, "extension property '%s' is read-only", key);
			}
			lua_pushvalue(L, 1);
			lua_pushvalue(L, 3);
			lua_call(L, 2, 0);
			return 0;
		}
	}

	luaL_error(L, "no field '%s' on %s", key, runtimeClassName(env, obj).c_str());
	return 0;
}

int jarrayIndex(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject array = userdataRef(L, 1);
	if (lua_type(L, 2) == LUA_TNUMBER)
	{
		int index = static_cast<int>(lua_tointeger(L, 2));
		jobject element = env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.arrayGet,
			array, index);
		checkJavaException(env, L);
		pushJava(env, L, element);
		if (element != nullptr)
		{
			env->DeleteLocalRef(element);
		}
		return 1;
	}
	const char* key = lua_tostring(L, 2);
	if (key == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}

	// Only the methods an array actually has (Object's) resolve; anything else is
	// nil, so callers can test for a member rather than getting a closure that
	// fails when called.
	jstring jkey = env->NewStringUTF(key);
	jobject member =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.getMember, array, jkey);
	env->DeleteLocalRef(jkey);
	checkJavaException(env, L);
	if (env->IsSameObject(member, g_bindings.methodValue))
	{
		env->DeleteLocalRef(member);
		pushBoundCall(L, 1, key, false);
		return 1;
	}
	env->DeleteLocalRef(member);

	lua_pushnil(L);
	return 1;
}

int jarrayNewIndex(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject array = userdataRef(L, 1);
	if (lua_type(L, 2) != LUA_TNUMBER)
	{
		luaL_error(L, "array index must be a number");
	}
	int index = static_cast<int>(lua_tointeger(L, 2));
	jobject value = luaToJava(env, L, 3);
	env->CallStaticVoidMethod(g_bindings.bridge, g_bindings.arraySet, array, index, value);
	checkJavaException(env, L);
	return 0;
}

int jarrayLen(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject array = userdataRef(L, 1);
	int length = env->CallStaticIntMethod(g_bindings.bridge, g_bindings.arrayLength, array);
	checkJavaException(env, L);
	lua_pushinteger(L, length);
	return 1;
}

// One step of a generic for over a Java array: takes the array and the previous
// index, and returns the next index and element. Ghidra hands back plain arrays
// all over its API (a p-code op's inputs, an instruction's operands, a symbol's
// references), so iterating one should read the same as iterating a Luau table.
int jarrayIterStep(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject array = userdataRef(L, 1);
	int index = static_cast<int>(lua_tointeger(L, 2)) + 1;
	int length = env->CallStaticIntMethod(g_bindings.bridge, g_bindings.arrayLength, array);
	checkJavaException(env, L);
	if (index > length)
	{
		lua_pushnil(L);
		return 1;
	}

	jobject element =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.arrayGet, array, index);
	checkJavaException(env, L);
	lua_pushinteger(L, index);
	pushJava(env, L, element);
	if (element != nullptr)
	{
		env->DeleteLocalRef(element);
	}
	return 2;
}

int jarrayIter(lua_State* L)
{
	lua_pushcfunction(L, jarrayIterStep, "next");
	lua_pushvalue(L, 1);
	lua_pushinteger(L, 0);
	return 3;
}

int jToString(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject obj = userdataRef(L, 1);
	jstring s =
		static_cast<jstring>(env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.display, obj));
	checkJavaException(env, L);
	if (s != nullptr)
	{
		const char* text = env->GetStringUTFChars(s, nullptr);
		lua_pushstring(L, text != nullptr ? text : "");
		if (text != nullptr)
		{
			env->ReleaseStringUTFChars(s, text);
		}
		env->DeleteLocalRef(s);
	}
	else
	{
		lua_pushstring(L, "null");
	}
	return 1;
}

// --- java.* module functions ---

bool endsWithStar(const char* name, size_t length)
{
	return length >= 2 && name[length - 2] == '.' && name[length - 1] == '*';
}

int javaImport(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	size_t length = 0;
	const char* name = luaL_checklstring(L, 1, &length);
	if (endsWithStar(name, length))
	{
		luaL_error(L, "java.import: package (.*) imports are not supported yet");
	}
	jstring jname = env->NewStringUTF(name);
	jobject clazz =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.importClass, jname);
	checkJavaException(env, L);
	pushClass(env, L, clazz);
	env->DeleteLocalRef(clazz);
	return 1;
}

int javaNew(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	env->EnsureLocalCapacity(32);
	jobject classObj = userdataRef(L, 1);
	if (classObj == nullptr)
	{
		luaL_error(L, "java.new: first argument must be a Java class");
	}
	int top = lua_gettop(L);
	jobjectArray args = collectArgs(env, L, 2, top);
	jobject result =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.construct, classObj, args);
	checkJavaException(env, L);
	pushJava(env, L, result);
	return 1;
}

int javaLuaify(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject ref = userdataRef(L, 1);
	if (ref == nullptr)
	{
		lua_pushvalue(L, 1);
		return 1;
	}
	pushJava(env, L, ref);
	return 1;
}

int javaArray(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jobject classObj = userdataRef(L, 1);
	if (classObj == nullptr)
	{
		luaL_error(L, "java.array: first argument must be a Java class");
	}
	int length = static_cast<int>(luaL_checkinteger(L, 2));
	jobject result =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.newArray, classObj, length);
	checkJavaException(env, L);
	pushJava(env, L, result);
	return 1;
}

// java.extend(className, { properties = {...}, methods = {...} })
//
// Registers Luau members for every instance of a Java class or interface. The
// names are checked against the Java class up front so an extension can never
// shadow a real Java field or method: lookups always try Java first, so a
// shadowing name would simply be unreachable.
int javaExtend(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	const char* className = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);

	jstring jclassName = env->NewStringUTF(className);
	jobject clazz =
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.importClass, jclassName);
	checkJavaException(env, L);
	if (clazz != nullptr)
	{
		env->DeleteLocalRef(clazz);
	}

	static const char* const sections[] = { "properties", "methods" };
	for (const char* section : sections)
	{
		lua_getfield(L, 2, section);
		if (lua_isnil(L, -1))
		{
			lua_pop(L, 1);
			continue;
		}
		if (!lua_istable(L, -1))
		{
			luaL_error(L, "java.extend: '%s' must be a table", section);
		}
		lua_pushnil(L);
		while (lua_next(L, -2) != 0)
		{
			const char* key = lua_tostring(L, -2);
			if (key != nullptr)
			{
				jstring jkey = env->NewStringUTF(key);
				jboolean clash = env->CallStaticBooleanMethod(g_bindings.bridge,
					g_bindings.hasMember, jclassName, jkey);
				env->DeleteLocalRef(jkey);
				if (clash)
				{
					luaL_error(L,
						"java.extend: '%s' already exists on %s; Luau extensions may not "
						"shadow Java members",
						key, className);
				}
			}
			lua_pop(L, 1);
		}
		lua_pop(L, 1);
	}
	env->DeleteLocalRef(jclassName);

	// Merge into any extension table already registered for this class so that
	// separate modules can each contribute members.
	lua_getfield(L, LUA_REGISTRYINDEX, EXT_KEY);
	lua_getfield(L, -1, className);
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 1);
		lua_newtable(L);
		lua_newtable(L);
		lua_setfield(L, -2, "properties");
		lua_newtable(L);
		lua_setfield(L, -2, "methods");
		lua_pushvalue(L, -1);
		lua_setfield(L, -3, className);
	}

	for (const char* section : sections)
	{
		lua_getfield(L, 2, section);
		if (!lua_istable(L, -1))
		{
			lua_pop(L, 1);
			continue;
		}
		lua_getfield(L, -2, section);
		lua_pushnil(L);
		while (lua_next(L, -3) != 0)
		{
			lua_pushvalue(L, -2);
			lua_insert(L, -2);
			lua_settable(L, -4);
		}
		lua_pop(L, 2);
	}
	lua_pop(L, 2);

	// Registering after a lookup would otherwise be masked by a stale merge.
	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, EXT_CACHE_KEY);
	return 0;
}

// java.proxy(interfaceName | { interfaceNames }, handler)
//
// Creates a Java object implementing the named interfaces, backed by a Luau
// handler: either a table of functions keyed by method name, or a single
// function used for every method (handy for functional interfaces).
int javaProxy(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	if (g_bindings.newProxy == nullptr)
	{
		luaL_error(L, "java.proxy is unavailable: luaghidra.bridge.LuaProxy was not found");
	}

	// Collect the interface names.
	std::vector<std::string> interfaces;
	if (lua_type(L, 1) == LUA_TSTRING)
	{
		interfaces.push_back(lua_tostring(L, 1));
	}
	else if (lua_istable(L, 1))
	{
		int count = lua_objlen(L, 1);
		for (int i = 1; i <= count; ++i)
		{
			lua_rawgeti(L, 1, i);
			const char* name = lua_tostring(L, -1);
			if (name == nullptr)
			{
				luaL_error(L, "java.proxy: interface names must be strings");
			}
			interfaces.push_back(name);
			lua_pop(L, 1);
		}
	}
	else
	{
		luaL_error(L, "java.proxy: expected an interface name or a list of them");
	}
	if (interfaces.empty())
	{
		luaL_error(L, "java.proxy: at least one interface is required");
	}

	int handlerType = lua_type(L, 2);
	if (handlerType != LUA_TTABLE && handlerType != LUA_TFUNCTION)
	{
		luaL_error(L, "java.proxy: the handler must be a table of functions or a function");
	}

	lua_getfield(L, LUA_REGISTRYINDEX, STATE_KEY);
	void* statePointer = lua_tolightuserdata(L, -1);
	lua_pop(L, 1);
	if (statePointer == nullptr)
	{
		luaL_error(L, "java.proxy is unavailable in this interpreter");
	}

	// Register the handler so the dispatcher can find it, keeping it alive for
	// as long as the interpreter lives.
	lua_getfield(L, LUA_REGISTRYINDEX, PROXY_KEY);
	int handlerId = lua_objlen(L, -1) + 1;
	lua_pushvalue(L, 2);
	lua_rawseti(L, -2, handlerId);
	lua_pop(L, 1);

	jclass stringClass = env->FindClass("java/lang/String");
	jobjectArray names =
		env->NewObjectArray(static_cast<jsize>(interfaces.size()), stringClass, nullptr);
	for (size_t i = 0; i < interfaces.size(); ++i)
	{
		jstring text = env->NewStringUTF(interfaces[i].c_str());
		env->SetObjectArrayElement(names, static_cast<jsize>(i), text);
		env->DeleteLocalRef(text);
	}

	jobject result = env->CallStaticObjectMethod(g_bindings.proxy, g_bindings.newProxy, names,
		static_cast<jlong>(reinterpret_cast<intptr_t>(statePointer)),
		static_cast<jlong>(handlerId));
	env->DeleteLocalRef(names);
	checkJavaException(env, L);
	pushJava(env, L, result);
	return 1;
}

// Returns the most recently captured Java Throwable, or nil if none.
int javaCaught(lua_State* L)
{
	lua_getfield(L, LUA_REGISTRYINDEX, CAUGHT_KEY);
	return 1;
}

// Java values are wrapped in a fresh userdata on every push, so identity
// comparison would report two references to the same object as different.
int jEquals(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jboolean equal = env->CallStaticBooleanMethod(g_bindings.bridge, g_bindings.valuesEqual,
		userdataRef(L, 1), userdataRef(L, 2));
	checkJavaException(env, L);
	lua_pushboolean(L, equal ? 1 : 0);
	return 1;
}

int compareRefs(lua_State* L)
{
	JNIEnv* env = luaghidra_getEnv();
	jint order = env->CallStaticIntMethod(g_bindings.bridge, g_bindings.compare,
		userdataRef(L, 1), userdataRef(L, 2));
	checkJavaException(env, L);
	return static_cast<int>(order);
}

int jLessThan(lua_State* L)
{
	lua_pushboolean(L, compareRefs(L) < 0 ? 1 : 0);
	return 1;
}

int jLessEqual(lua_State* L)
{
	lua_pushboolean(L, compareRefs(L) <= 0 ? 1 : 0);
	return 1;
}

// Luau only consults a comparison metamethod when both operands carry the *same*
// metamethod value, so the three metatables have to share one closure each
// rather than getting their own.
void installComparisons(lua_State* L)
{
	static const char* const META_KEYS[] = { META_CLASS_KEY, META_OBJECT_KEY, META_ARRAY_KEY };
	struct Operation
	{
		const char* name;
		lua_CFunction fn;
	};
	static const Operation OPERATIONS[] = {
		{ "__eq", jEquals },
		{ "__lt", jLessThan },
		{ "__le", jLessEqual },
	};

	for (const Operation& operation : OPERATIONS)
	{
		lua_pushcfunction(L, operation.fn, operation.name);
		for (const char* key : META_KEYS)
		{
			lua_getfield(L, LUA_REGISTRYINDEX, key);
			lua_pushvalue(L, -2);
			lua_setfield(L, -2, operation.name);
			lua_pop(L, 1);
		}
		lua_pop(L, 1);
	}
}

void setFunction(lua_State* L, const char* name, lua_CFunction fn)
{
	lua_pushcfunction(L, fn, name);
	lua_setfield(L, -2, name);
}

void buildMetatable(lua_State* L, const char* key, bool isClass)
{
	lua_newtable(L);

	lua_pushcfunction(L, isClass ? jclassIndex : jobjectIndex, "__index");
	lua_setfield(L, -2, "__index");

	lua_pushcfunction(L, isClass ? jclassNewIndex : jobjectNewIndex, "__newindex");
	lua_setfield(L, -2, "__newindex");

	lua_pushcfunction(L, isClass ? jclassNamecall : jobjectNamecall, "__namecall");
	lua_setfield(L, -2, "__namecall");

	lua_pushcfunction(L, jToString, "__tostring");
	lua_setfield(L, -2, "__tostring");

	if (isClass)
	{
		lua_pushcfunction(L, jclassCall, "__call");
		lua_setfield(L, -2, "__call");
	}

	lua_pushstring(L, "locked");
	lua_setfield(L, -2, "__metatable");

	lua_setfield(L, LUA_REGISTRYINDEX, key);
}

void buildArrayMetatable(lua_State* L)
{
	lua_newtable(L);

	lua_pushcfunction(L, jarrayIndex, "__index");
	lua_setfield(L, -2, "__index");

	lua_pushcfunction(L, jarrayNewIndex, "__newindex");
	lua_setfield(L, -2, "__newindex");

	lua_pushcfunction(L, jarrayLen, "__len");
	lua_setfield(L, -2, "__len");

	lua_pushcfunction(L, jarrayIter, "__iter");
	lua_setfield(L, -2, "__iter");

	lua_pushcfunction(L, jobjectNamecall, "__namecall");
	lua_setfield(L, -2, "__namecall");

	lua_pushcfunction(L, jToString, "__tostring");
	lua_setfield(L, -2, "__tostring");

	lua_pushstring(L, "locked");
	lua_setfield(L, -2, "__metatable");

	lua_setfield(L, LUA_REGISTRYINDEX, META_ARRAY_KEY);
}

void refDtor(lua_State*, void* ud)
{
	jobject* p = static_cast<jobject*>(ud);
	if (*p != nullptr)
	{
		JNIEnv* env = luaghidra_getEnv();
		if (env != nullptr)
		{
			env->DeleteGlobalRef(*p);
		}
		*p = nullptr;
	}
}
}

namespace
{
void collectExtensionNames(lua_State* L, const char* section, std::vector<std::string>& out)
{
	lua_getfield(L, -1, section);
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 1);
		return;
	}
	lua_pushnil(L);
	while (lua_next(L, -2) != 0)
	{
		if (lua_type(L, -2) == LUA_TSTRING)
		{
			out.push_back(lua_tostring(L, -2));
		}
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
}
}

std::vector<std::string> luaghidra_memberNames(JNIEnv* env, lua_State* L, int index)
{
	std::vector<std::string> names;
	if (!initBindings(env))
	{
		return names;
	}

	int absolute = lua_absindex(L, index);
	jobject ref = userdataRef(L, absolute);
	if (ref == nullptr)
	{
		return names;
	}

	// A jclass userdata holds the Class itself, so its members are the static
	// ones; anything else reports its runtime class.
	std::string className;
	if (lua_userdatatag(L, absolute) == TAG_CLASS)
	{
		jstring declared = static_cast<jstring>(
			env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.declaredClassName, ref));
		className = javaString(env, declared);
		if (declared != nullptr)
		{
			env->DeleteLocalRef(declared);
		}
	}
	else
	{
		className = runtimeClassName(env, ref);
	}

	jstring jname = env->NewStringUTF(className.c_str());
	jobjectArray members = static_cast<jobjectArray>(
		env->CallStaticObjectMethod(g_bindings.bridge, g_bindings.memberNames, jname));
	env->DeleteLocalRef(jname);
	if (env->ExceptionCheck())
	{
		env->ExceptionClear();
		return names;
	}

	int count = members != nullptr ? static_cast<int>(env->GetArrayLength(members)) : 0;
	for (int i = 0; i < count; ++i)
	{
		jstring element = static_cast<jstring>(env->GetObjectArrayElement(members, i));
		names.push_back(javaString(env, element));
		if (element != nullptr)
		{
			env->DeleteLocalRef(element);
		}
	}
	if (members != nullptr)
	{
		env->DeleteLocalRef(members);
	}

	int base = lua_gettop(L);
	if (pushExtensions(env, L, ref))
	{
		collectExtensionNames(L, "properties", names);
		collectExtensionNames(L, "methods", names);
	}
	lua_settop(L, base);
	return names;
}

bool luaghidra_pushProxyHandler(lua_State* L, int handlerId, const char* method)
{
	lua_getfield(L, LUA_REGISTRYINDEX, PROXY_KEY);
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 1);
		return false;
	}
	lua_rawgeti(L, -1, handlerId);
	lua_remove(L, -2);

	if (lua_isfunction(L, -1))
	{
		return true;
	}
	if (lua_istable(L, -1))
	{
		lua_getfield(L, -1, method);
		lua_remove(L, -2);
		if (lua_isfunction(L, -1))
		{
			return true;
		}
	}
	lua_pop(L, 1);
	return false;
}

void luaghidra_checkJavaException(JNIEnv* env, lua_State* L)
{
	checkJavaException(env, L);
}

jobject luaghidra_toJava(JNIEnv* env, lua_State* L, int index)
{
	if (!initBindings(env))
	{
		return nullptr;
	}
	return luaToJava(env, L, index);
}

void luaghidra_pushJava(JNIEnv* env, lua_State* L, jobject value)
{
	if (!initBindings(env))
	{
		lua_pushnil(L);
		return;
	}
	pushJava(env, L, value);
}

JNIEnv* luaghidra_getEnv()
{
	if (g_vm == nullptr)
	{
		return nullptr;
	}
	JNIEnv* env = nullptr;
	jint status = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_8);
	if (status == JNI_OK)
	{
		return env;
	}
	if (status == JNI_EDETACHED)
	{
		if (g_vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr) == JNI_OK)
		{
			return env;
		}
	}
	return nullptr;
}

void luaghidra_installJavaModule(JNIEnv* env, lua_State* L)
{
	if (!initBindings(env))
	{
		return;
	}

	lua_setuserdatadtor(L, TAG_CLASS, refDtor);
	lua_setuserdatadtor(L, TAG_OBJECT, refDtor);
	lua_setuserdatadtor(L, TAG_ARRAY, refDtor);

	buildMetatable(L, META_CLASS_KEY, true);
	buildMetatable(L, META_OBJECT_KEY, false);
	buildArrayMetatable(L);
	installComparisons(L);

	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, PROXY_KEY);

	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, EXT_KEY);
	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, EXT_CACHE_KEY);

	luaghidra_runSource(L, EXT_MERGE_SOURCE, "=luaghidra.extmerge", 1);
	lua_setfield(L, LUA_REGISTRYINDEX, EXT_MERGE_KEY);

	lua_newtable(L);
	setFunction(L, "import", javaImport);
	setFunction(L, "new", javaNew);
	setFunction(L, "luaify", javaLuaify);
	setFunction(L, "array", javaArray);
	setFunction(L, "caught", javaCaught);
	setFunction(L, "extend", javaExtend);
	setFunction(L, "proxy", javaProxy);
	lua_setglobal(L, "java");
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*)
{
	g_vm = vm;
	return JNI_VERSION_1_8;
}
