#include "luau_util.h"

extern "C"
{
#include <luacode.h>
#include <lualib.h>
}

#include <cstdlib>
#include <cstring>

int luaghidra_loadSource(lua_State* L, const char* source, size_t length, const char* chunkName)
{
	lua_CompileOptions options = {};
	options.optimizationLevel = 1;
	options.debugLevel = 1;

	size_t bytecodeSize = 0;
	char* bytecode = luau_compile(source, length, &options, &bytecodeSize);
	if (bytecode == nullptr)
	{
		lua_pushstring(L, "luau_compile returned no bytecode");
		return LUA_ERRSYNTAX;
	}

	int status = luau_load(L, chunkName, bytecode, bytecodeSize, 0);
	std::free(bytecode);
	return status;
}

void luaghidra_runSource(lua_State* L, const char* source, const char* chunkName, int results)
{
	if (luaghidra_loadSource(L, source, std::strlen(source), chunkName) != LUA_OK)
	{
		lua_error(L);
	}
	lua_call(L, 0, results);
}

bool luaghidra_isIncomplete(const std::string& message)
{
	return message.find("<eof>") != std::string::npos;
}
