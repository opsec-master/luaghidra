package luaghidra.runtime;

import luaghidra.LuaEvalResult;
import luaghidra.LuauNativeBridge;

/**
 * A Luau interpreter state with the LuaGhidra runtime installed.
 *
 * <p>
 * Wraps the native handle so callers do not deal with raw {@code long}s, and
 * ties the state's lifetime to {@link #close()}. Each interpreter has its own
 * globals, module cache, and Java extension registry.
 */
public final class LuaInterpreter implements AutoCloseable {

	private final long state;
	private LuaGhidraContext context;
	private boolean closed;

	private LuaInterpreter(long state) {
		this.state = state;
	}

	/**
	 * Creates an interpreter.
	 *
	 * @throws IllegalStateException when the native state could not be created
	 */
	public static LuaInterpreter create() {
		long state = LuauNativeBridge.newState();
		if (state == 0) {
			throw new IllegalStateException("could not create a Luau interpreter state");
		}
		return new LuaInterpreter(state);
	}

	/**
	 * Publishes the Ghidra context this interpreter's scripts run against, making
	 * {@code require("@ghidra")} work.
	 */
	public void setContext(LuaGhidraContext context) {
		checkOpen();
		this.context = context;
		LuauNativeBridge.setHost(state, context);
	}

	public LuaGhidraContext getContext() {
		return context;
	}

	/** Streams {@code print} output to {@code sink}, or buffers it when null. */
	public void setOutput(LuaOutput sink) {
		checkOpen();
		LuauNativeBridge.setOutput(state, sink);
	}

	/** Binds a Java value as a Lua global. */
	public void setGlobal(String name, Object value) {
		checkOpen();
		LuauNativeBridge.setGlobal(state, name, value);
	}

	/** Evaluates one console entry, echoing the value of a bare expression. */
	public LuaEvalResult eval(String source) {
		checkOpen();
		return LuauNativeBridge.eval(state, source);
	}

	/** Runs a whole script file. */
	public LuaEvalResult runScript(String chunkName, String source) {
		checkOpen();
		return LuauNativeBridge.runScript(state, chunkName, source);
	}

	/** Member names reachable through a dotted path; empty path means globals. */
	public String[] completions(String path) {
		checkOpen();
		return LuauNativeBridge.completions(state, path);
	}

	@Override
	public void close() {
		if (closed) {
			return;
		}
		closed = true;
		if (context != null) {
			context.dispose();
			context = null;
		}
		LuauNativeBridge.closeState(state);
	}

	private void checkOpen() {
		if (closed) {
			throw new IllegalStateException("the interpreter has been closed");
		}
	}
}
