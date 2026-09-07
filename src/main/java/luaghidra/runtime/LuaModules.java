package luaghidra.runtime;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Resolves {@code require(...)} requests for the Luau runtime.
 *
 * <p>
 * Two request shapes are supported, matching Luau's own require conventions:
 *
 * <ul>
 * <li><b>aliases</b> — {@code @ghidra}, {@code @ghidra/decompiler}: resolved
 * against the modules shipped inside the extension jar, under
 * {@code /luaghidra/modules/}.</li>
 * <li><b>relative paths</b> — {@code ./helpers}, {@code ../lib/util}: resolved
 * against the directory of the requiring chunk and read from disk.</li>
 * </ul>
 *
 * <p>
 * Bare names such as {@code require("helpers")} are rejected so that a script's
 * dependencies are always unambiguous.
 *
 * <p>
 * Called from native code; see {@code src/main/native/require.cpp}.
 */
public final class LuaModules {

	private static final String RESOURCE_ROOT = "/luaghidra/modules/";

	/**
	 * Extra directories searched for alias modules, after the modules bundled in
	 * the extension so that a stray file cannot shadow {@code @ghidra}.
	 */
	private static final List<Path> userRoots = new ArrayList<>();

	private LuaModules() {
	}

	/**
	 * Adds a directory that alias requires may resolve against, after the modules
	 * bundled in the extension. Lets a script directory carry its own alias
	 * modules without being able to shadow the shipped ones.
	 */
	public static synchronized void addUserRoot(Path root) {
		if (root != null && Files.isDirectory(root) && !userRoots.contains(root)) {
			userRoots.add(0, root);
		}
	}

	public static synchronized void clearUserRoots() {
		userRoots.clear();
	}

	private static synchronized List<Path> userRoots() {
		return List.copyOf(userRoots);
	}

	/**
	 * Resolves a require request.
	 *
	 * @param fromChunk the chunk name of the requiring script, used as the base
	 *            for relative requests; may be {@code null} for the console
	 * @param request the string passed to {@code require}
	 * @return {@code { resolvedName, source }}, or {@code null} when the module
	 *         does not exist
	 * @throws IllegalArgumentException when the request shape is not supported
	 */
	public static String[] resolve(String fromChunk, String request) {
		if (request == null || request.isEmpty()) {
			throw new IllegalArgumentException("require expects a non-empty module name");
		}
		if (request.startsWith("@")) {
			return resolveAlias(request);
		}
		if (request.startsWith("./") || request.startsWith("../")) {
			return resolveRelative(fromChunk, request);
		}
		throw new IllegalArgumentException("require(\"" + request
				+ "\") is not a valid module name; use \"@ghidra\" for built-in modules "
				+ "or \"./" + request + "\" for a file next to this script");
	}

	private static String[] resolveAlias(String request) {
		String path = request.substring(1);
		if (path.isEmpty() || path.contains("..")) {
			throw new IllegalArgumentException("invalid module alias: " + request);
		}

		for (String candidate : candidates(path)) {
			String source = readResource(RESOURCE_ROOT + candidate);
			if (source != null) {
				return new String[] { "@" + path, source };
			}
		}

		for (Path root : userRoots()) {
			for (String candidate : candidates(path)) {
				String source = readFile(root.resolve(candidate));
				if (source != null) {
					return new String[] { "@" + path, source };
				}
			}
		}
		return null;
	}

	private static List<String> candidates(String path) {
		return List.of(path + ".luau", path + "/init.luau");
	}

	private static String[] resolveRelative(String fromChunk, String request) {
		Path base = chunkDirectory(fromChunk);
		if (base == null) {
			throw new IllegalArgumentException("require(\"" + request
					+ "\") needs a script file to resolve against; "
					+ "relative requires are not available in the console");
		}
		Path target = base.resolve(request).normalize();
		for (String suffix : List.of(".luau", ".lua", "/init.luau")) {
			Path file = Path.of(target + suffix);
			String source = readFile(file);
			if (source != null) {
				return new String[] { file.toString(), source };
			}
		}
		return null;
	}

	private static Path chunkDirectory(String fromChunk) {
		if (fromChunk == null || fromChunk.isEmpty() || fromChunk.startsWith("@")) {
			return null;
		}
		Path path = Path.of(fromChunk).toAbsolutePath();
		Path parent = path.getParent();
		return parent != null && Files.isDirectory(parent) ? parent : null;
	}

	private static String readFile(Path file) {
		try {
			if (!Files.isRegularFile(file)) {
				return null;
			}
			return Files.readString(file, StandardCharsets.UTF_8);
		}
		catch (IOException e) {
			return null;
		}
	}

	/**
	 * Returns the paths of the Luau modules bundled in the extension, relative to
	 * the module root (for example {@code "ghidra/init.luau"}).
	 *
	 * <p>
	 * Read from an index generated at build time, because the modules live in a
	 * jar and a jar's contents cannot be listed through {@code getResource}.
	 */
	public static List<String> bundledModulePaths() {
		String index = readResource("/luaghidra/modules.index");
		if (index == null) {
			return List.of();
		}
		return index.lines().map(String::trim).filter(line -> !line.isEmpty()).toList();
	}

	/** Returns the source of a bundled module by its relative path. */
	public static String bundledModuleSource(String relativePath) {
		return readResource(RESOURCE_ROOT + relativePath);
	}

	private static String readResource(String resource) {
		try (InputStream in = LuaModules.class.getResourceAsStream(resource)) {
			if (in == null) {
				return null;
			}
			return new String(in.readAllBytes(), StandardCharsets.UTF_8);
		}
		catch (IOException e) {
			return null;
		}
	}
}
