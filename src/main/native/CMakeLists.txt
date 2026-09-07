cmake_minimum_required(VERSION 3.21)

project(LuaGhidraNative LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(JNI REQUIRED)

if(NOT LUAU_SOURCE_DIR)
    message(FATAL_ERROR "LUAU_SOURCE_DIR is required")
endif()

if(NOT LUAU_ARTIFACT_DIR)
    message(FATAL_ERROR "LUAU_ARTIFACT_DIR is required")
endif()

set(LUAU_LIB_DIR "${LUAU_ARTIFACT_DIR}/lib")

# The staged archives keep the toolchain's own naming: libLuau.VM.a with the GNU
# and Apple toolchains, Luau.VM.lib with MSVC.
function(add_luau_static target)
    add_library(${target} STATIC IMPORTED GLOBAL)
    set_target_properties(${target} PROPERTIES
        IMPORTED_LOCATION
            "${LUAU_LIB_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${target}${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
endfunction()

add_luau_static(Luau.Common)
add_luau_static(Luau.Ast)
add_luau_static(Luau.Bytecode)
add_luau_static(Luau.Compiler)
add_luau_static(Luau.VM)

add_library(luaghidra SHARED
    luaghidra_jni.cpp
    java_bridge.cpp
    luau_require.cpp
    luau_util.cpp
)

target_include_directories(luaghidra
    PRIVATE
        ${JNI_INCLUDE_DIRS}
        "${LUAU_SOURCE_DIR}/Compiler/include"
        "${LUAU_SOURCE_DIR}/VM/include"
        "${LUAU_SOURCE_DIR}/Common/include"
)

target_link_libraries(luaghidra
    PRIVATE
        Luau.Compiler
        Luau.VM
        Luau.Bytecode
        Luau.Ast
        Luau.Common
)

if(APPLE)
    set_target_properties(luaghidra PROPERTIES
        INSTALL_NAME_DIR "@rpath"
    )
endif()

# The shipped library has to load on whatever distribution Ghidra runs on, so it
# carries the C++ runtime it was built against rather than requiring it.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_options(luaghidra PRIVATE -static-libstdc++ -static-libgcc)
endif()
