package luaghidra.console;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import ghidra.app.plugin.core.console.CodeCompletion;
import luaghidra.runtime.LuaInterpreter;

/**
 * Completes identifiers in the interpreter console.
 *
 * <p>
 * Completion resolves the dotted path left of the caret in the live interpreter,
 * so it offers the members a value actually has: Lua table keys, Java fields and
 * methods, and the Luau extension properties and methods registered for a Java
 * class. Only paths made of identifiers joined by {@code .} are resolved, so
 * pressing the completion key never calls a function or indexes with a
 * subscript.
 */
final class LuaCompletions {

	/**
	 * The identifier chain at the end of the input: an optional dotted base, an
	 * optional {@code .} or {@code :} separator, and the partial name being typed.
	 */
	private static final Pattern TAIL = Pattern.compile(
		"(?:([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)\\s*([.:]))?([A-Za-z_][A-Za-z0-9_]*)?$");

	private LuaCompletions() {
	}

	static List<CodeCompletion> compute(LuaInterpreter interpreter, String command, int caretPos) {
		if (interpreter == null || command == null) {
			return List.of();
		}
		int caret = Math.max(0, Math.min(caretPos, command.length()));
		Matcher matcher = TAIL.matcher(command.substring(0, caret));
		if (!matcher.find()) {
			return List.of();
		}

		String base = matcher.group(1);
		String separator = matcher.group(2);
		String partial = matcher.group(3) == null ? "" : matcher.group(3);
		if (base == null && partial.isEmpty()) {
			return List.of();
		}

		String[] names;
		try {
			names = interpreter.completions(base == null ? "" : base);
		}
		catch (Throwable t) {
			return List.of();
		}

		// A ':' call only makes sense for methods, but the interpreter cannot tell
		// a method from a field without calling it, so both are offered.
		boolean methodCall = ":".equals(separator);
		List<CodeCompletion> completions = new ArrayList<>();
		for (String name : names) {
			if (!name.startsWith(partial) || name.equals(partial)) {
				continue;
			}
			if (base == null && name.startsWith("__")) {
				continue;
			}
			String insertion = name.substring(partial.length());
			completions.add(new CodeCompletion(methodCall ? name + "(...)" : name, insertion, null));
		}
		completions.sort(null);
		return completions;
	}
}
