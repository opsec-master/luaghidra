package luaghidra;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import generic.jar.ResourceFile;
import ghidra.app.script.GhidraScript;
import ghidra.app.script.GhidraState;
import ghidra.app.script.ScriptControls;
import ghidra.program.model.listing.Program;
import ghidra.util.task.TaskMonitor;
import luaghidra.runtime.LuaEditorSetup;
import luaghidra.script.LuauScriptProvider;
import luaghidra.runtime.LuaGhidraContext;
import luaghidra.runtime.LuaInterpreter;
import luaghidra.runtime.LuaModules;

/**
 * Runs the {@code .luau} test suite outside Ghidra.
 *
 * <p>
 * Each file under {@code src/test/luau} is executed in a fresh interpreter
 * state; a test fails when the script raises an error. Tests that need Ghidra
 * classes are skipped automatically when Ghidra is not on the classpath, which
 * keeps the bridge-level suite runnable from a plain Gradle invocation.
 *
 * <p>
 * Run with {@code gradle luaTest}.
 */
public final class LuauTestRunner {

	public static void main(String[] args) throws IOException {
		Path root = Path.of(args.length > 0 ? args[0] : "src/test/luau");
		if (args.length > 1) {
			LuaModules.addUserRoot(Path.of(args[1]));
		}

		List<Path> scripts = new ArrayList<>();
		try (var stream = Files.walk(root)) {
			stream.filter(p -> p.getFileName().toString().endsWith(".luau"))
					.filter(p -> !p.toString().contains("fixtures"))
					.sorted(Comparator.comparing(Path::toString))
					.forEach(scripts::add);
		}

		boolean ghidraAvailable = true;
		try {
			TestProgram.create(LuauTestRunner.class).release(LuauTestRunner.class);
		}
		catch (Throwable t) {
			ghidraAvailable = false;
			System.out.println("note: Ghidra could not be initialized (" + t
					+ "); @ghidra tests will be skipped");
		}

		// The shipped examples are run too: they are the API's front door, so a
		// change that breaks one should fail the suite.
		Path examples = Path.of("ghidra_scripts");
		if (Files.isDirectory(examples)) {
			try (var stream = Files.list(examples)) {
				stream.filter(p -> p.getFileName().toString().endsWith(".luau"))
						.sorted(Comparator.comparing(Path::toString))
						.forEach(scripts::add);
			}
		}

		int failed = 0;
		int skipped = 0;
		for (Path script : scripts) {
			// Files numbered 20 and up, and the examples, exercise the @ghidra
			// module and need a program; lower numbers cover the bridge alone.
			boolean needsGhidra = leadingNumber(script) >= 20
					|| script.startsWith("ghidra_scripts");
			if (needsGhidra && !ghidraAvailable) {
				System.out.println("SKIP " + script + " (no Ghidra)");
				skipped++;
				continue;
			}
			if (!run(script, needsGhidra)) {
				failed++;
			}
		}

		if (!checkCompletions()) {
			failed++;
		}
		if (!checkEditorSetup()) {
			failed++;
		}
		if (ghidraAvailable && !checkScriptProvider()) {
			failed++;
		}

		System.out.println();
		System.out.printf("%d test file(s), %d failure(s), %d skipped%n", scripts.size(), failed,
			skipped);
		if (failed > 0) {
			System.exit(1);
		}
	}

	/** The number a test file's name starts with, or -1 when it has none. */
	private static int leadingNumber(Path script) {
		String name = script.getFileName().toString();
		int end = 0;
		while (end < name.length() && Character.isDigit(name.charAt(end))) {
			end++;
		}
		return end == 0 ? -1 : Integer.parseInt(name.substring(0, end));
	}

	/**
	 * Runs one test file. Each file that needs a program gets a fresh one, so a
	 * test that mutates the database cannot affect the next.
	 */
	private static boolean run(Path script, boolean needsGhidra) throws IOException {
		String source = Files.readString(script, StandardCharsets.UTF_8);
		StringBuilder output = new StringBuilder();
		StringWriter consoleText = new StringWriter();

		if (source.contains("require(\"@ghidra/ui\")")) {
			// Prompts have no answer in this runner; headless Ghidra would read
			// them from a .properties file next to the script.
			System.out.println("SKIP " + script + " (prompts for input)");
			return true;
		}

		Program program = null;
		try (LuaInterpreter interpreter = LuaInterpreter.create()) {
			interpreter.setOutput(output::append);
			if (needsGhidra) {
				program = TestProgram.create(LuauTestRunner.class);
				interpreter.setContext(
					TestProgram.contextFor(program, new PrintWriter(consoleText, true)));
			}

			LuaEvalResult result =
				interpreter.runScript(script.toAbsolutePath().toString(), source);
			output.append(consoleText.toString());
			if (result.isError()) {
				System.out.println("FAIL " + script);
				System.out.print(indent(output.toString()));
				System.out.print(indent(result.message()));
				return false;
			}
			System.out.println("PASS " + script);
			if (!output.isEmpty()) {
				System.out.print(indent(output.toString()));
			}
			return true;
		}
		catch (Throwable t) {
			System.out.println("FAIL " + script + ": " + t);
			return false;
		}
		finally {
			if (program != null) {
				program.release(LuauTestRunner.class);
			}
		}
	}

	/** Console completion has no Luau-visible surface, so it is checked here. */
	private static boolean checkCompletions() {
		try (LuaInterpreter interpreter = LuaInterpreter.create()) {
			interpreter.eval("x = java.import(\"java.lang.Integer\")");
			interpreter.eval("t = { alpha = 1, beta = 2 }");

			if (!contains(interpreter.completions(""), "java", "require", "print")) {
				System.out.println("FAIL completions: globals");
				return false;
			}
			if (!contains(interpreter.completions("x"), "parseInt", "MAX_VALUE")) {
				System.out.println("FAIL completions: Java static members");
				return false;
			}
			if (!contains(interpreter.completions("t"), "alpha", "beta")) {
				System.out.println("FAIL completions: table keys");
				return false;
			}
			if (interpreter.completions("nosuchglobal").length != 0) {
				System.out.println("FAIL completions: unknown path should be empty");
				return false;
			}
			System.out.println("PASS completions");
			return true;
		}
		catch (Throwable t) {
			System.out.println("FAIL completions: " + t);
			return false;
		}
	}

	/**
	 * Runs a script through the provider, which is the path the Script Manager and
	 * headless analyzer take. The Luau suite runs scripts directly, so this is the
	 * only check that the GhidraScript wiring holds together.
	 */
	private static boolean checkScriptProvider() {
		Program program = null;
		try {
			program = TestProgram.create(LuauTestRunner.class);
			StringWriter text = new StringWriter();
			PrintWriter writer = new PrintWriter(text, true);

			LuauScriptProvider provider = new LuauScriptProvider();
			ResourceFile source = new ResourceFile(
				Path.of("ghidra_scripts/LuauListFunctions.luau").toAbsolutePath().toFile());
			GhidraScript script = provider.getScriptInstance(source, writer);

			GhidraState state = new GhidraState(null, null, program, null, null, null);
			script.execute(state, new ScriptControls(writer, writer, TaskMonitor.DUMMY));

			boolean ok = text.toString().contains("main");
			System.out.println(ok ? "PASS script provider" : "FAIL script provider");
			if (!ok) {
				System.out.print(indent(text.toString()));
			}
			return ok;
		}
		catch (Throwable t) {
			System.out.println("FAIL script provider: " + t);
			return false;
		}
		finally {
			if (program != null) {
				program.release(LuauTestRunner.class);
			}
		}
	}

	/** The editor setup writes files, so it is checked into a temp directory. */
	private static boolean checkEditorSetup() {
		try {
			Path directory = Files.createTempDirectory("luaghidra-editor");
			Path modules = LuaEditorSetup.install(directory);
			boolean ok = Files.isRegularFile(directory.resolve(".luaurc"))
					&& Files.isRegularFile(modules.resolve("ghidra/init.luau"))
					&& Files.readString(directory.resolve(".luaurc")).contains("\"ghidra\"");
			System.out.println(ok ? "PASS editor setup" : "FAIL editor setup");
			try (var walk = Files.walk(directory)) {
				walk.sorted(Comparator.reverseOrder()).forEach(path -> path.toFile().delete());
			}
			return ok;
		}
		catch (Throwable t) {
			System.out.println("FAIL editor setup: " + t);
			return false;
		}
	}

	private static boolean contains(String[] values, String... expected) {
		List<String> actual = List.of(values);
		for (String name : expected) {
			if (!actual.contains(name)) {
				System.out.println("    missing: " + name + " (got " + actual + ")");
				return false;
			}
		}
		return true;
	}

	private static String indent(String text) {
		return text.lines().map(line -> "    " + line).reduce("", (a, b) -> a + b + "\n");
	}
}
