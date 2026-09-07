package luaghidra.script;

/**
 * Raised when a Luau script fails, carrying the Luau error message and
 * traceback. Thrown from {@link LuauScript#run()} so Ghidra reports the failure
 * the same way it reports a Java script's exception.
 */
public class LuauScriptException extends Exception {

	private static final long serialVersionUID = 1L;

	public LuauScriptException(String message) {
		super(message);
	}

	@Override
	public synchronized Throwable fillInStackTrace() {
		// The Luau traceback is already in the message; a Java stack trace here
		// would only point at the bridge.
		return this;
	}
}
