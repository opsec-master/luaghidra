#include <jni.h>

extern "C"
{
#include <lua.h>
#include <lualib.h>
}

#include "java_bridge.h"
#include "luau_require.h"
#include "luau_util.h"

#include <cstdint>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace
{
// Per-interpreter state shared across evaluations.
//
// Output written by print/warn either streams to a Java sink (used by the script
// runner, so long scripts report progress as they go) or accumulates in a buffer
// that a single console evaluation returns at the end.
struct LuaConsoleState
{
	lua_State* L = nullptr;
	std::string output;
	jobject sink = nullptr;
	jmethodID sinkWrite = nullptr;
	// The thread currently inside this state, so a java.proxy call made from
	// somewhere else can be refused instead of corrupting the interpreter.
	std::thread::id owner{};
	bool running = false;
};

void throwRuntimeException(JNIEnv* env, const char* message)
{
	jclass exceptionClass = env->FindClass("java/lang/RuntimeException");
	if (exceptionClass != nullptr)
	{
		env->ThrowNew(exceptionClass, message);
	}
}

void throwNullPointerException(JNIEnv* env, const char* message)
{
	jclass exceptionClass = env->FindClass("java/lang/NullPointerException");
	if (exceptionClass != nullptr)
	{
		env->ThrowNew(exceptionClass, message);
	}
}

LuaConsoleState* consoleFromState(lua_State* L)
{
	return static_cast<LuaConsoleState*>(lua_getthreaddata(L));
}

LuaConsoleState* fromHandle(jlong handle)
{
	return reinterpret_cast<LuaConsoleState*>(static_cast<intptr_t>(handle));
}

void emit(LuaConsoleState* console, const char* text, size_t length)
{
	if (console->sink != nullptr && console->sinkWrite != nullptr)
	{
		JNIEnv* env = luaghidra_getEnv();
		if (env != nullptr)
		{
			jstring chunk = env->NewStringUTF(std::string(text, length).c_str());
			env->CallVoidMethod(console->sink, console->sinkWrite, chunk);
			env->DeleteLocalRef(chunk);
			if (env->ExceptionCheck())
			{
				env->ExceptionClear();
			}
			return;
		}
	}
	console->output.append(text, length);
}

void appendValue(LuaConsoleState* console, lua_State* L, int index)
{
	size_t len = 0;
	const char* text = luaL_tolstring(L, index, &len);
	if (text != nullptr)
	{
		emit(console, text, len);
	}
	// luaL_tolstring pushes the converted string; drop it.
	lua_pop(L, 1);
}

// Replacement for the base library 'print' that redirects to the console.
int luaPrint(lua_State* L)
{
	LuaConsoleState* console = consoleFromState(L);
	if (console == nullptr)
	{
		return 0;
	}

	int count = lua_gettop(L);
	for (int i = 1; i <= count; ++i)
	{
		if (i > 1)
		{
			emit(console, "\t", 1);
		}
		appendValue(console, L, i);
	}
	emit(console, "\n", 1);
	return 0;
}

// Error handler installed for every pcall so runtime errors carry a traceback.
int addTraceback(lua_State* L)
{
	const char* message = lua_tostring(L, 1);
	luaL_traceback(L, L, message != nullptr ? message : "error", 1);
	return 1;
}

std::string stackString(lua_State* L, int index)
{
	size_t len = 0;
	const char* text = lua_tolstring(L, index, &len);
	if (text == nullptr)
	{
		return std::string();
	}
	return std::string(text, len);
}

jobjectArray makeResult(JNIEnv* env, const char* status, const std::string& output,
	const std::string& message)
{
	jclass stringClass = env->FindClass("java/lang/String");
	if (stringClass == nullptr)
	{
		return nullptr;
	}

	jobjectArray result = env->NewObjectArray(3, stringClass, nullptr);
	if (result == nullptr)
	{
		return nullptr;
	}

	env->SetObjectArrayElement(result, 0, env->NewStringUTF(status));
	env->SetObjectArrayElement(result, 1, env->NewStringUTF(output.c_str()));
	env->SetObjectArrayElement(result, 2, env->NewStringUTF(message.c_str()));
	return result;
}

std::string jstringToStd(JNIEnv* env, jstring value)
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
}

extern "C" JNIEXPORT jstring JNICALL Java_luaghidra_LuauNativeBridge_nativeVersion(
	JNIEnv* env, jclass)
{
	return env->NewStringUTF("Luau (LuaGhidra JNI bridge)");
}

extern "C" JNIEXPORT jboolean JNICALL Java_luaghidra_LuauNativeBridge_nativeCanCompile(
	JNIEnv* env, jclass, jstring source)
{
	if (source == nullptr)
	{
		throwNullPointerException(env, "source");
		return JNI_FALSE;
	}

	std::string text = jstringToStd(env, source);
	lua_State* state = luaL_newstate();
	if (state == nullptr)
	{
		return JNI_FALSE;
	}

	int status = luaghidra_loadSource(state, text.c_str(), text.size(), "=LuaGhidra");
	lua_close(state);
	return status == LUA_OK ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL Java_luaghidra_LuauNativeBridge_nativeNewState(
	JNIEnv* env, jclass)
{
	LuaConsoleState* console = new (std::nothrow) LuaConsoleState();
	if (console == nullptr)
	{
		return 0;
	}

	console->L = luaL_newstate();
	if (console->L == nullptr)
	{
		delete console;
		return 0;
	}

	lua_State* L = console->L;
	luaL_openlibs(L);
	lua_setthreaddata(L, console);

	lua_pushcfunction(L, luaPrint, "print");
	lua_setglobal(L, "print");

	// java.proxy needs to name this state when it registers a handler.
	lua_pushlightuserdata(L, console);
	lua_setfield(L, LUA_REGISTRYINDEX, "luaghidra.state");

	luaghidra_installJavaModule(env, L);
	luaghidra_installRequire(env, L);

	return static_cast<jlong>(reinterpret_cast<intptr_t>(console));
}

extern "C" JNIEXPORT void JNICALL Java_luaghidra_LuauNativeBridge_nativeCloseState(
	JNIEnv* env, jclass, jlong handle)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr)
	{
		return;
	}

	if (console->L != nullptr)
	{
		lua_close(console->L);
		console->L = nullptr;
	}
	if (console->sink != nullptr)
	{
		env->DeleteGlobalRef(console->sink);
		console->sink = nullptr;
	}
	delete console;
}

// Redirects print output to a luaghidra.runtime.LuaOutput, or restores buffering
// when 'sink' is null.
extern "C" JNIEXPORT void JNICALL Java_luaghidra_LuauNativeBridge_nativeSetOutput(
	JNIEnv* env, jclass, jlong handle, jobject sink)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr)
	{
		return;
	}

	if (console->sink != nullptr)
	{
		env->DeleteGlobalRef(console->sink);
		console->sink = nullptr;
		console->sinkWrite = nullptr;
	}
	if (sink == nullptr)
	{
		return;
	}

	jclass sinkClass = env->GetObjectClass(sink);
	console->sinkWrite = env->GetMethodID(sinkClass, "write", "(Ljava/lang/String;)V");
	env->DeleteLocalRef(sinkClass);
	if (console->sinkWrite != nullptr)
	{
		console->sink = env->NewGlobalRef(sink);
	}
}

// Binds a Java value as a Lua global, using the same conversions as the java
// module: booleans, numbers, and strings arrive as Lua values, everything else
// as a jobject.
extern "C" JNIEXPORT void JNICALL Java_luaghidra_LuauNativeBridge_nativeSetGlobal(
	JNIEnv* env, jclass, jlong handle, jstring name, jobject value)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr || console->L == nullptr || name == nullptr)
	{
		throwNullPointerException(env, "interpreter state");
		return;
	}

	lua_State* L = console->L;
	std::string globalName = jstringToStd(env, name);
	luaghidra_pushJava(env, L, value);
	lua_setglobal(L, globalName.c_str());
}

// Publishes a luaghidra.runtime.LuaGhidraContext as require("@host"), which is
// what the @ghidra module is built on.
extern "C" JNIEXPORT void JNICALL Java_luaghidra_LuauNativeBridge_nativeSetHost(
	JNIEnv* env, jclass, jlong handle, jobject host)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr || console->L == nullptr)
	{
		throwNullPointerException(env, "interpreter state");
		return;
	}
	luaghidra_setHostModule(env, console->L, host);
}

namespace
{
// Runs a loaded chunk under a traceback error handler. The chunk must be on top
// of the stack; 'base' is the stack top before it was pushed.
int callChunk(lua_State* L, int base)
{
	lua_pushcfunction(L, addTraceback, "traceback");
	lua_insert(L, base + 1);
	int status = lua_pcall(L, 0, LUA_MULTRET, base + 1);
	lua_remove(L, base + 1);
	return status;
}

jobjectArray evalChunk(JNIEnv* env, LuaConsoleState* console, const std::string& source,
	const char* chunkName, bool echoExpression)
{
	lua_State* L = console->L;
	console->output.clear();
	console->owner = std::this_thread::get_id();
	console->running = true;
	lua_settop(L, 0);

	// Try evaluating as an expression first so the REPL can echo its value.
	bool isExpression = echoExpression;
	int loadStatus = LUA_ERRSYNTAX;
	if (echoExpression)
	{
		std::string wrapped = "return " + source;
		loadStatus = luaghidra_loadSource(L, wrapped.c_str(), wrapped.size(), chunkName);
		if (loadStatus != LUA_OK)
		{
			lua_pop(L, 1); // discard the expression load error
			isExpression = false;
		}
	}

	if (loadStatus != LUA_OK)
	{
		loadStatus = luaghidra_loadSource(L, source.c_str(), source.size(), chunkName);
		if (loadStatus != LUA_OK)
		{
			std::string message = stackString(L, -1);
			lua_settop(L, 0);
			console->running = false;
			if (echoExpression && luaghidra_isIncomplete(message))
			{
				return makeResult(env, "incomplete", std::string(), std::string());
			}
			return makeResult(env, "error", console->output, message);
		}
	}

	int base = lua_gettop(L) - 1;
	if (callChunk(L, base) != LUA_OK)
	{
		std::string message = stackString(L, -1);
		lua_settop(L, 0);
		console->running = false;
		return makeResult(env, "error", console->output, message);
	}

	if (isExpression)
	{
		int results = lua_gettop(L) - base;
		for (int i = 1; i <= results; ++i)
		{
			if (i > 1)
			{
				emit(console, "\t", 1);
			}
			appendValue(console, L, base + i);
		}
		if (results > 0)
		{
			emit(console, "\n", 1);
		}
	}

	lua_settop(L, 0);
	console->running = false;
	return makeResult(env, "ok", console->output, std::string());
}
}

// Dispatches a java.proxy call back into Luau. Called from
// luaghidra.bridge.LuaProxy on the thread that made the Java call.
extern "C" JNIEXPORT jobject JNICALL Java_luaghidra_LuauNativeBridge_nativeInvokeProxy(
	JNIEnv* env, jclass, jlong handle, jlong handlerId, jstring method, jobjectArray args)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr || console->L == nullptr)
	{
		throwRuntimeException(env, "the interpreter that created this proxy has been closed");
		return nullptr;
	}
	if (!console->running || console->owner != std::this_thread::get_id())
	{
		throwRuntimeException(env,
			"a Luau proxy may only be called from the thread running its interpreter");
		return nullptr;
	}

	lua_State* L = console->L;
	std::string name = jstringToStd(env, method);
	int base = lua_gettop(L);

	if (!luaghidra_pushProxyHandler(L, static_cast<int>(handlerId), name.c_str()))
	{
		lua_settop(L, base);
		throwRuntimeException(env, ("the Luau proxy has no handler for '" + name + "'").c_str());
		return nullptr;
	}

	int count = args != nullptr ? static_cast<int>(env->GetArrayLength(args)) : 0;
	for (int i = 0; i < count; ++i)
	{
		jobject argument = env->GetObjectArrayElement(args, i);
		luaghidra_pushJava(env, L, argument);
		if (argument != nullptr)
		{
			env->DeleteLocalRef(argument);
		}
	}

	if (lua_pcall(L, count, 1, 0) != LUA_OK)
	{
		std::string message = stackString(L, -1);
		lua_settop(L, base);
		throwRuntimeException(env, ("Luau proxy handler failed: " + message).c_str());
		return nullptr;
	}

	jobject result = luaghidra_toJava(env, L, -1);
	lua_settop(L, base);
	return result;
}

// Evaluates one console entry. Returns a String[3]: { status, output, message }
// where status is one of "ok", "error", or "incomplete".
extern "C" JNIEXPORT jobjectArray JNICALL Java_luaghidra_LuauNativeBridge_nativeEval(
	JNIEnv* env, jclass, jlong handle, jstring source)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr || console->L == nullptr)
	{
		throwNullPointerException(env, "interpreter state");
		return nullptr;
	}
	if (source == nullptr)
	{
		throwNullPointerException(env, "source");
		return nullptr;
	}

	return evalChunk(env, console, jstringToStd(env, source), "=stdin", true);
}

namespace
{
// Appends every string key of the table at the top of the stack.
void collectTableKeys(lua_State* L, std::vector<std::string>& out)
{
	lua_pushnil(L);
	while (lua_next(L, -2) != 0)
	{
		if (lua_type(L, -2) == LUA_TSTRING)
		{
			out.push_back(lua_tostring(L, -2));
		}
		lua_pop(L, 1);
	}
}

// Appends the names a Java value responds to: its public members, plus any Luau
// extension properties and methods registered for its class.
void collectJavaMembers(JNIEnv* env, lua_State* L, std::vector<std::string>& out)
{
	std::vector<std::string> names = luaghidra_memberNames(env, L, -1);
	out.insert(out.end(), names.begin(), names.end());
}

jobjectArray toStringArray(JNIEnv* env, const std::vector<std::string>& values)
{
	jclass stringClass = env->FindClass("java/lang/String");
	if (stringClass == nullptr)
	{
		return nullptr;
	}
	jobjectArray result =
		env->NewObjectArray(static_cast<jsize>(values.size()), stringClass, nullptr);
	for (size_t i = 0; i < values.size(); ++i)
	{
		jstring text = env->NewStringUTF(values[i].c_str());
		env->SetObjectArrayElement(result, static_cast<jsize>(i), text);
		env->DeleteLocalRef(text);
	}
	return result;
}
}

// Returns the member names available on a dotted path, for console completion.
// An empty path enumerates globals. The path is evaluated, so callers must only
// pass side-effect-free expressions; the console restricts it to identifiers
// joined by dots.
extern "C" JNIEXPORT jobjectArray JNICALL Java_luaghidra_LuauNativeBridge_nativeCompletions(
	JNIEnv* env, jclass, jlong handle, jstring path)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr || console->L == nullptr)
	{
		return toStringArray(env, {});
	}

	lua_State* L = console->L;
	int base = lua_gettop(L);
	std::vector<std::string> names;
	std::string expression = jstringToStd(env, path);

	if (expression.empty())
	{
		lua_pushvalue(L, LUA_GLOBALSINDEX);
		collectTableKeys(L, names);
	}
	else
	{
		std::string source = "return " + expression;
		if (luaghidra_loadSource(L, source.c_str(), source.size(), "=completion") == LUA_OK
			&& lua_pcall(L, 0, 1, 0) == LUA_OK)
		{
			int type = lua_type(L, -1);
			if (type == LUA_TTABLE)
			{
				collectTableKeys(L, names);
			}
			else if (type == LUA_TUSERDATA)
			{
				collectJavaMembers(env, L, names);
			}
		}
	}

	lua_settop(L, base);
	return toStringArray(env, names);
}

// Runs a whole script file. 'chunkName' should be the script's path so that
// error messages and relative requires resolve against it.
extern "C" JNIEXPORT jobjectArray JNICALL Java_luaghidra_LuauNativeBridge_nativeRunScript(
	JNIEnv* env, jclass, jlong handle, jstring chunkName, jstring source)
{
	LuaConsoleState* console = fromHandle(handle);
	if (console == nullptr || console->L == nullptr)
	{
		throwNullPointerException(env, "interpreter state");
		return nullptr;
	}
	if (source == nullptr)
	{
		throwNullPointerException(env, "source");
		return nullptr;
	}

	std::string name = "@" + jstringToStd(env, chunkName);
	return evalChunk(env, console, jstringToStd(env, source), name.c_str(), false);
}
