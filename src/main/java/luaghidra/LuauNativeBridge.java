package luaghidra;

import java.io.File;

import ghidra.framework.Application;
import ghidra.framework.OSFileNotFoundException;
import ghidra.framework.Platform;
import luaghidra.bridge.LuaProxy;
import luaghidra.runtime.LuaOutput;

public final class LuauNativeBridge {
	private static final String LIBRARY_NAME = "luaghidra";

	private static volatile boolean loaded;

	private LuauNativeBridge() {
	}

	/**
	 * Loads the JNI bridge, looking in this order:
	 *
	 * <ol>
	 * <li>the path in the {@code luaghidra.library.path} system property, which
	 * lets tests and headless tools point at a build tree;</li>
	 * <li>Ghidra's extension {@code os/<platform>} directory;</li>
	 * <li>{@code java.library.path}.</li>
	 * </ol>
	 */
	public static synchronized void load() {
		if (loaded) {
			return;
		}

		String mappedLibraryName = System.mapLibraryName(LIBRARY_NAME);
		String override = System.getProperty("luaghidra.library.path");
		if (override != null && !override.isEmpty()) {
			File file = new File(override);
			System.load(file.isDirectory() ? new File(file, mappedLibraryName).getAbsolutePath()
					: file.getAbsolutePath());
			loaded = true;
			return;
		}

		try {
			File libraryFile = Application.getOSFile(mappedLibraryName);
			System.load(libraryFile.getAbsolutePath());
		}
		catch (OSFileNotFoundException | IllegalStateException | NullPointerException e) {
			// Not running inside an initialized Ghidra application.
			System.loadLibrary(LIBRARY_NAME);
		}

		loaded = true;
	}

	public static String version() {
		load();
		return nativeVersion();
	}

	public static boolean canCompile(String source) {
		load();
		return nativeCanCompile(source);
	}

	/**
	 * Creates a new persistent Luau interpreter state.
	 *
	 * @return an opaque native handle, or {@code 0} if creation failed
	 */
	public static long newState() {
		load();
		return nativeNewState();
	}

	/**
	 * Closes a Luau interpreter state previously returned by {@link #newState()}.
	 *
	 * @param state the native handle (a no-op when {@code 0})
	 */
	public static void closeState(long state) {
		if (state != 0) {
			nativeCloseState(state);
		}
	}

	/**
	 * Evaluates a chunk of Luau source against a persistent interpreter state.
	 *
	 * @param state the native handle from {@link #newState()}
	 * @param source the Luau source to evaluate
	 * @return a {@link LuaEvalResult} describing the outcome
	 */
	public static LuaEvalResult eval(long state, String source) {
		load();
		String[] result = nativeEval(state, source);
		LuaEvalStatus status = LuaEvalStatus.fromNative(result[0]);
		return new LuaEvalResult(status, result[1], result[2]);
	}

	/**
	 * Runs a whole script against a state.
	 *
	 * @param state the native handle from {@link #newState()}
	 * @param chunkName the script's path; used in error messages and as the base
	 *            for relative {@code require} calls
	 * @param source the Luau source
	 * @return a {@link LuaEvalResult}; never {@link LuaEvalStatus#INCOMPLETE}
	 */
	public static LuaEvalResult runScript(long state, String chunkName, String source) {
		load();
		String[] result = nativeRunScript(state, chunkName, source);
		LuaEvalStatus status = LuaEvalStatus.fromNative(result[0]);
		return new LuaEvalResult(status, result[1], result[2]);
	}

	/**
	 * Redirects the state's {@code print} output to a sink, or restores buffering
	 * when {@code sink} is {@code null}.
	 */
	public static void setOutput(long state, LuaOutput sink) {
		load();
		nativeSetOutput(state, sink);
	}

	/**
	 * Binds a Java value as a Lua global in the given state.
	 *
	 * <p>
	 * Booleans, numbers, and strings arrive on the Lua side as plain Lua values;
	 * anything else arrives as a {@code jobject} userdata with the same member
	 * access as {@code java.new(...)} results.
	 */
	public static void setGlobal(long state, String name, Object value) {
		load();
		nativeSetGlobal(state, name, value);
	}

	/**
	 * Publishes {@code host} as the result of {@code require("@host")} in the
	 * given state, which is what the {@code @ghidra} module is built on.
	 *
	 * @param host a {@link luaghidra.runtime.LuaGhidraContext}, or {@code null} to
	 *            remove it
	 */
	public static void setHost(long state, Object host) {
		load();
		nativeSetHost(state, host);
	}

	/**
	 * Returns the member names reachable through a dotted path, for console
	 * completion. An empty path enumerates globals.
	 *
	 * <p>
	 * The path is evaluated in the interpreter, so callers must restrict it to
	 * side-effect-free expressions.
	 */
	public static String[] completions(long state, String path) {
		load();
		return nativeCompletions(state, path == null ? "" : path);
	}

	static {
		LuaProxy.setDispatcher(LuauNativeBridge::nativeInvokeProxy);
	}

	public static String platformLibraryName() {
		return System.mapLibraryName(LIBRARY_NAME);
	}

	public static String ghidraPlatformName() {
		return Platform.CURRENT_PLATFORM.getDirectoryName();
	}

	private static native String nativeVersion();

	private static native boolean nativeCanCompile(String source);

	private static native long nativeNewState();

	private static native void nativeCloseState(long state);

	private static native String[] nativeEval(long state, String source);

	private static native String[] nativeRunScript(long state, String chunkName, String source);

	private static native void nativeSetOutput(long state, LuaOutput sink);

	private static native void nativeSetGlobal(long state, String name, Object value);

	private static native void nativeSetHost(long state, Object host);

	private static native String[] nativeCompletions(long state, String path);

	private static native Object nativeInvokeProxy(long state, long handlerId, String method,
			Object[] args);
}
