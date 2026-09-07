package luaghidra.runtime;

import java.io.IOException;
import java.io.PrintWriter;
import java.nio.file.Path;
import java.util.Iterator;
import java.util.List;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.script.GhidraScript;
import ghidra.app.script.GhidraState;
import ghidra.app.script.ScriptControls;
import ghidra.framework.plugintool.PluginTool;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFormatException;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Program;
import ghidra.program.model.mem.MemoryAccessException;
import ghidra.program.util.DefinedDataIterator;
import ghidra.program.util.ProgramLocation;
import ghidra.program.util.ProgramSelection;
import ghidra.util.task.TaskMonitor;

/**
 * The host object the {@code @ghidra} Luau module is built on.
 *
 * <p>
 * Scripts reach it with {@code require("@host")}, but are expected to go through
 * {@code require("@ghidra")} instead. Everything here is either state the Luau
 * side cannot reach on its own (the current program, tool, and monitor) or a
 * handful of operations that are markedly easier in Java than through
 * reflection, such as building a predicate-driven iterator.
 *
 * <p>
 * A context wraps a {@link GhidraScript}, which is what both the interpreter
 * console and the {@code .luau} script provider supply, so the same module works
 * in the console, in the script manager, and headless.
 */
public final class LuaGhidraContext {

	private final GhidraScript script;

	private DecompInterface decompiler;
	private Program decompilerProgram;

	public LuaGhidraContext(GhidraScript script) {
		this.script = script;
	}

	// --- state ---

	public GhidraScript getScript() {
		return script;
	}

	public GhidraState getState() {
		return script.getState();
	}

	public Program getProgram() {
		return script.getState().getCurrentProgram();
	}

	public PluginTool getTool() {
		return script.getState().getTool();
	}

	public TaskMonitor getMonitor() {
		ScriptControls controls = script.getControls();
		TaskMonitor monitor = controls == null ? null : controls.getMonitor();
		return monitor != null ? monitor : TaskMonitor.DUMMY;
	}

	public Address getCurrentAddress() {
		return script.getState().getCurrentAddress();
	}

	public ProgramLocation getCurrentLocation() {
		return script.getState().getCurrentLocation();
	}

	public ProgramSelection getCurrentSelection() {
		return script.getState().getCurrentSelection();
	}

	public ProgramSelection getCurrentHighlight() {
		return script.getState().getCurrentHighlight();
	}

	public String[] getArgs() {
		String[] args = script.getScriptArgs();
		return args != null ? args : new String[0];
	}

	public boolean isHeadless() {
		return script.isRunningHeadless();
	}

	// --- output ---

	public void println(String message) {
		script.println(message == null ? "" : message);
	}

	/**
	 * Writes to the error stream.
	 *
	 * <p>
	 * Goes straight to the writer rather than through
	 * {@link GhidraScript#printerr}, which prefixes the message with the Java
	 * class running the script — {@code LuauScript.class>} for every Luau script,
	 * which says nothing about which script produced the line.
	 */
	public void printerr(String message) {
		ScriptControls controls = script.getControls();
		PrintWriter writer = controls == null ? null : controls.getErrorWriter();
		if (writer == null) {
			script.printerr(message == null ? "" : message);
			return;
		}
		writer.println(message == null ? "" : message);
		writer.flush();
	}

	public void setStatus(String message) {
		TaskMonitor monitor = getMonitor();
		if (monitor != null) {
			monitor.setMessage(message);
		}
	}

	// --- addresses ---

	/**
	 * Coerces a Lua-supplied value to an {@link Address} in the program's default
	 * address space.
	 *
	 * @param value an {@code Address}, a numeric offset, or a string parsed by the
	 *            program's address factory (accepting both {@code "00401000"} and
	 *            {@code "ram:00401000"})
	 * @throws IllegalArgumentException when the value cannot be interpreted
	 */
	public Address toAddress(Object value) {
		return toAddress(value, null);
	}

	/**
	 * Coerces a Lua-supplied value to an {@link Address} in a named space.
	 *
	 * <p>
	 * A numeric offset is taken as an offset within {@code space}, which matters
	 * on architectures with more than one memory space and for overlays. An
	 * {@code Address} is returned unchanged, since it already names its space.
	 *
	 * @param space an {@code AddressSpace}, a space name, or {@code null} for the
	 *            program's default space
	 */
	public Address toAddress(Object value, Object space) {
		if (value == null) {
			return null;
		}
		if (value instanceof Address address) {
			return address;
		}

		AddressSpace target = space == null ? null : toAddressSpace(space);
		if (value instanceof Number number) {
			AddressSpace in =
				target != null ? target : requireProgram().getAddressFactory()
						.getDefaultAddressSpace();
			return in.getAddress(number.longValue());
		}
		if (value instanceof String text) {
			String trimmed = text.trim();
			Address address = target != null ? parseIn(target, trimmed)
					: requireProgram().getAddressFactory().getAddress(trimmed);
			if (address == null) {
				throw new IllegalArgumentException("not a valid address: " + text);
			}
			return address;
		}
		throw new IllegalArgumentException(
			"cannot use a " + value.getClass().getName() + " as an address");
	}

	private static Address parseIn(AddressSpace space, String text) {
		try {
			return space.getAddress(text);
		}
		catch (AddressFormatException e) {
			return null;
		}
	}

	/**
	 * Resolves an {@link AddressSpace} from itself or its name.
	 *
	 * @throws IllegalArgumentException naming the spaces this program has, when
	 *             the name matches none of them
	 */
	public AddressSpace toAddressSpace(Object value) {
		if (value instanceof AddressSpace space) {
			return space;
		}
		if (!(value instanceof String name)) {
			throw new IllegalArgumentException(
				"cannot use a " + (value == null ? "nil" : value.getClass().getName())
						+ " as an address space");
		}
		AddressSpace space = requireProgram().getAddressFactory().getAddressSpace(name);
		if (space == null) {
			throw new IllegalArgumentException(
				"no address space called '" + name + "'; this program has " + spaceNames());
		}
		return space;
	}

	private String spaceNames() {
		StringBuilder names = new StringBuilder();
		for (AddressSpace space : requireProgram().getAddressFactory().getAllAddressSpaces()) {
			if (names.length() > 0) {
				names.append(", ");
			}
			names.append(space.getName());
		}
		return names.toString();
	}

	public AddressSetView toAddressSet(Object start, Object end) {
		return new AddressSet(toAddress(start), toAddress(end));
	}

	// --- iteration helpers that need a Java predicate ---

	/**
	 * Returns an iterator over every defined string in the program, which the
	 * Luau side cannot build because it needs a Java {@code Predicate}.
	 */
	public Iterator<Data> definedStrings() {
		return DefinedDataIterator.byDataInstance(requireProgram(), StringDataInstance::isString);
	}

	/**
	 * Returns the string value of a defined data item, or {@code null} when it is
	 * not string data.
	 */
	public String stringValue(Data data) {
		if (data == null || !StringDataInstance.isString(data)) {
			return null;
		}
		StringDataInstance instance = StringDataInstance.getStringDataInstance(data);
		return instance == null ? null : instance.getStringValue();
	}

	// --- memory ---

	public byte[] readBytes(Object address, int length) throws MemoryAccessException {
		if (length < 0) {
			throw new IllegalArgumentException("length must not be negative");
		}
		byte[] bytes = new byte[length];
		requireProgram().getMemory().getBytes(toAddress(address), bytes);
		return bytes;
	}

	public void writeBytes(Object address, byte[] bytes) throws MemoryAccessException {
		requireProgram().getMemory().setBytes(toAddress(address), bytes);
	}

	// --- decompiler ---

	/**
	 * Returns a decompiler opened on the current program, created on first use and
	 * reused afterwards. Reopened automatically when the program changes.
	 */
	public DecompInterface getDecompiler() {
		Program program = requireProgram();
		if (decompiler != null && decompilerProgram == program) {
			return decompiler;
		}
		disposeDecompiler();
		DecompInterface created = new DecompInterface();
		if (!created.openProgram(program)) {
			String message = created.getLastMessage();
			created.dispose();
			throw new IllegalStateException(
				"could not open the decompiler: " + (message == null ? "unknown error" : message));
		}
		decompiler = created;
		decompilerProgram = program;
		return decompiler;
	}

	public void disposeDecompiler() {
		if (decompiler != null) {
			decompiler.dispose();
			decompiler = null;
			decompilerProgram = null;
		}
	}

	/**
	 * Sets a directory up for editing {@code .luau} files with type checking. See
	 * {@link LuaEditorSetup}.
	 *
	 * @return the directory the modules were written to
	 */
	public String setUpEditor(String scriptDirectory) throws IOException {
		return LuaEditorSetup.install(Path.of(scriptDirectory)).toString();
	}

	/** Releases resources held by this context. */
	public void dispose() {
		disposeDecompiler();
	}

	// --- internals ---

	private Program requireProgram() {
		Program program = getProgram();
		if (program == null) {
			throw new IllegalStateException("no program is open");
		}
		return program;
	}

	/**
	 * A {@link GhidraScript} with no body, used as the state carrier for contexts
	 * that are not backed by a script file, such as the interpreter console.
	 */
	public static final class HostScript extends GhidraScript {

		@Override
		protected void run() {
			// Nothing to run; this script only carries state.
		}
	}

	/**
	 * Builds a context for a console or other host that is not backed by a script
	 * file.
	 *
	 * @param state the Ghidra state to track
	 * @param controls the output writers and task monitor scripts should use
	 */
	public static LuaGhidraContext forHost(GhidraState state, ScriptControls controls) {
		HostScript host = new HostScript();
		host.set(state, controls);
		host.setPotentialPropertiesFileLocations(List.of());
		return new LuaGhidraContext(host);
	}
}
