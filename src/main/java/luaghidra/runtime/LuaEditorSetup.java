package luaghidra.runtime;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Sets a script directory up for editing {@code .luau} files with type checking.
 *
 * <p>
 * Extracts the bundled {@code @ghidra} modules next to the user's scripts and
 * writes a {@code .luaurc} that points the {@code @ghidra} alias at them, so
 * <a href="https://github.com/JohnnyMorganz/luau-lsp">luau-lsp</a> resolves
 * {@code require("@ghidra")} to real source and offers types and completion.
 *
 * <p>
 * The extracted copy is only for the editor; the interpreter always reads the
 * modules from inside the extension jar. Re-running the setup refreshes the copy
 * after an extension upgrade.
 */
public final class LuaEditorSetup {

	/** Directory the modules are extracted into, relative to the script directory. */
	public static final String MODULES_DIRECTORY = ".luaghidra";

	private LuaEditorSetup() {
	}

	/**
	 * Installs the module copy and {@code .luaurc} into a script directory.
	 *
	 * @param scriptDirectory the directory holding the user's {@code .luau} files
	 * @return the directory the modules were written to
	 * @throws IOException when the files could not be written
	 * @throws IllegalStateException when the extension carries no module index
	 */
	public static Path install(Path scriptDirectory) throws IOException {
		List<String> paths = LuaModules.bundledModulePaths();
		if (paths.isEmpty()) {
			throw new IllegalStateException(
				"the extension does not carry a module index; rebuild it with 'gradle buildExtension'");
		}

		Path root = scriptDirectory.resolve(MODULES_DIRECTORY);
		for (String relative : paths) {
			String source = LuaModules.bundledModuleSource(relative);
			if (source == null) {
				continue;
			}
			Path target = root.resolve(relative);
			Files.createDirectories(target.getParent());
			Files.writeString(target, source, StandardCharsets.UTF_8);
		}

		Files.writeString(scriptDirectory.resolve(".luaurc"), luaurc(), StandardCharsets.UTF_8);
		return root;
	}

	private static String luaurc() {
		return """
				{
				  "languageMode": "nonstrict",
				  "aliases": {
				    "ghidra": "./%s/ghidra"
				  }
				}
				""".formatted(MODULES_DIRECTORY);
	}
}
