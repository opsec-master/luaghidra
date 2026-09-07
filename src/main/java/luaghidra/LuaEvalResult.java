package luaghidra;

/**
 * Result of evaluating a chunk of Luau source in the interpreter.
 *
 * @param status the evaluation outcome
 * @param output text captured from {@code print} and echoed expression values
 * @param message the error message when {@link #status()} is {@link LuaEvalStatus#ERROR}
 */
public record LuaEvalResult(LuaEvalStatus status, String output, String message) {

	public boolean isOk() {
		return status == LuaEvalStatus.OK;
	}

	public boolean isError() {
		return status == LuaEvalStatus.ERROR;
	}

	public boolean isIncomplete() {
		return status == LuaEvalStatus.INCOMPLETE;
	}

	public boolean hasOutput() {
		return output != null && !output.isEmpty();
	}
}
