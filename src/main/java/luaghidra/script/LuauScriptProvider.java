package luaghidra.script;

import java.io.IOException;
import java.io.PrintWriter;

import generic.jar.ResourceFile;
import ghidra.app.script.GhidraScript;
import ghidra.app.script.GhidraScriptLoadException;
import ghidra.app.script.GhidraScriptProvider;
import luaghidra.LuauNativeBridge;

/**
 * Registers {@code .luau} files as Ghidra scripts.
 *
 * <p>
 * Discovered automatically as an extension point, so any {@code .luau} file in a
 * script directory shows up in the Script Manager and can be run headless with
 * {@code analyzeHeadless ... -postScript name.luau}.
 */
public class LuauScriptProvider extends GhidraScriptProvider {

	@Override
	public String getDescription() {
		return "Luau";
	}

	@Override
	public String getExtension() {
		return ".luau";
	}

	@Override
	public String getCommentCharacter() {
		return "--";
	}

	@Override
	public String getRuntimeEnvironmentName() {
		return "Luau";
	}

	@Override
	public GhidraScript getScriptInstance(ResourceFile sourceFile, PrintWriter writer)
			throws GhidraScriptLoadException {
		try {
			LuauNativeBridge.load();
		}
		catch (Throwable t) {
			throw new GhidraScriptLoadException(
				"the LuaGhidra native bridge could not be loaded: " + t.getMessage(), t);
		}

		LuauScript script = new LuauScript();
		script.setSourceFile(sourceFile);
		return script;
	}

	@Override
	public void createNewScript(ResourceFile newScript, String category) throws IOException {
		try (PrintWriter writer = new PrintWriter(newScript.getOutputStream())) {
			writeHeader(writer, category);
			writer.println("local ghidra = require(\"@ghidra\")");
			writer.println();
			writeBody(writer);
			writer.println();
		}
	}
}
