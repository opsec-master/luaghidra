package luaghidra.script;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;

import generic.jar.ResourceFile;
import ghidra.app.script.GhidraScript;
import ghidra.app.script.ScriptControls;
import luaghidra.LuaEvalResult;
import luaghidra.runtime.LuaGhidraContext;
import luaghidra.runtime.LuaInterpreter;
import luaghidra.runtime.LuaModules;

/**
 * A {@code .luau} file run as a Ghidra script.
 *
 * <p>
 * The script gets a fresh interpreter with {@code require("@ghidra")} bound to
 * this script's state, so the same file behaves identically in the Script
 * Manager, from the console, and headless. {@code print} streams to the Ghidra
 * console as the script runs rather than being held until it finishes.
 */
public class LuauScript extends GhidraScript {

	@Override
	protected void run() throws Exception {
		ResourceFile file = getSourceFile();
		if (file == null) {
			throw new IllegalStateException("no source file for this Luau script");
		}

		// Lets a script directory carry its own alias modules, for example
		// require("@mylib"). Relative requires resolve from the script's path and
		// need no root.
		ResourceFile parent = file.getParentFile();
		java.io.File parentDirectory = parent == null ? null : parent.getFile(false);
		if (parentDirectory != null) {
			LuaModules.addUserRoot(parentDirectory.toPath());
		}

		String source = read(file);
		PrintWriter out = writerFor();
		try (LuaInterpreter interpreter = LuaInterpreter.create()) {
			interpreter.setContext(new LuaGhidraContext(this));
			interpreter.setOutput(text -> {
				out.print(text);
				out.flush();
			});

			LuaEvalResult result =
				interpreter.runScript(file.getAbsolutePath(), source);
			if (result.hasOutput()) {
				out.print(result.output());
				out.flush();
			}
			if (result.isError()) {
				throw new LuauScriptException(result.message());
			}
		}
	}

	private PrintWriter writerFor() {
		ScriptControls controls = getControls();
		PrintWriter out = controls == null ? null : controls.getWriter();
		return out != null ? out : new PrintWriter(System.out, true);
	}

	private static String read(ResourceFile file) throws IOException {
		try (InputStream in = file.getInputStream()) {
			return new String(in.readAllBytes(), StandardCharsets.UTF_8);
		}
	}

	@Override
	public String getCategory() {
		return "Luau";
	}
}
