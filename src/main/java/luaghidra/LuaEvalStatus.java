package luaghidra;

/**
 * Outcome categories for a single Luau console evaluation.
 */
public enum LuaEvalStatus {
	/** The chunk ran to completion. */
	OK,
	/** The chunk failed to compile or raised an error while running. */
	ERROR,
	/** The chunk is syntactically incomplete and more input is required. */
	INCOMPLETE;

	static LuaEvalStatus fromNative(String value) {
		if (value == null) {
			return ERROR;
		}
		switch (value) {
			case "ok":
				return OK;
			case "incomplete":
				return INCOMPLETE;
			case "error":
			default:
				return ERROR;
		}
	}
}
