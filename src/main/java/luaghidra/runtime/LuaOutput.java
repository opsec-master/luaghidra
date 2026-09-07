package luaghidra.runtime;

/**
 * Receives text written by a Luau state's {@code print}.
 *
 * <p>
 * Installed through {@link luaghidra.LuauNativeBridge#setOutput}. When no sink
 * is installed the native side buffers output and returns it from each
 * evaluation instead, which is what the console does.
 */
@FunctionalInterface
public interface LuaOutput {

	/**
	 * Writes a chunk of output. Chunks are not line-delimited; newlines arrive as
	 * part of the text.
	 */
	void write(String text);
}
