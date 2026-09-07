package luaghidra;

import java.io.PrintWriter;

import ghidra.GhidraApplicationLayout;
import ghidra.app.script.GhidraState;
import ghidra.app.script.ScriptControls;
import ghidra.framework.Application;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.framework.HeadlessGhidraApplicationConfiguration;
import ghidra.program.database.ProgramDB;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.CompilerSpec;
import ghidra.program.model.lang.Language;
import ghidra.program.model.lang.LanguageID;
import ghidra.program.model.listing.Program;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.util.DefaultLanguageService;
import ghidra.util.task.TaskMonitor;
import luaghidra.runtime.LuaGhidraContext;

/**
 * Builds a small in-memory program so the {@code @ghidra} module can be tested
 * without a Ghidra project or a real binary.
 *
 * <p>
 * Initializing Ghidra headlessly can fail in a bare environment; callers treat a
 * null context as "skip the Ghidra-dependent tests" rather than a failure, so
 * the bridge-level suite still runs.
 */
public final class TestProgram {

	private static boolean initialized;

	private TestProgram() {
	}

	public static synchronized void initializeGhidra() throws Exception {
		if (initialized) {
			return;
		}
		if (!Application.isInitialized()) {
			Application.initializeApplication(new GhidraApplicationLayout(),
				new HeadlessGhidraApplicationConfiguration());
		}
		initialized = true;
	}

	/**
	 * x86-64 code for {@code main}, which sets up a frame, calls {@code helper},
	 * loads a return value, and returns. Real instructions rather than filler, so
	 * disassembly, references, basic blocks, and P-code all have something to
	 * work with.
	 */
	private static final byte[] MAIN = {
		0x55, // push rbp
		0x48, (byte) 0x89, (byte) 0xe5, // mov rbp, rsp
		(byte) 0xe8, (byte) 0xf7, 0x00, 0x00, 0x00, // call helper (0x401100)
		(byte) 0xb8, 0x01, 0x00, 0x00, 0x00, // mov eax, 1
		0x5d, // pop rbp
		(byte) 0xc3, // ret
	};

	/** x86-64 code for {@code helper}: loads 42 and returns. */
	private static final byte[] HELPER = {
		(byte) 0xb8, 0x2a, 0x00, 0x00, 0x00, // mov eax, 42
		(byte) 0xc3, // ret
	};

	/**
	 * Creates a program with one 4KB executable block at 0x401000 holding two
	 * disassembled functions, a label, and room for tests to define data.
	 */
	public static Program create(Object consumer) throws Exception {
		initializeGhidra();

		Language language = DefaultLanguageService.getLanguageService()
				.getLanguage(new LanguageID("x86:LE:64:default"));
		CompilerSpec compilerSpec = language.getDefaultCompilerSpec();
		ProgramDB program = new ProgramDB("scratch", language, compilerSpec, consumer);

		int transaction = program.startTransaction("build");
		try {
			Address base = address(program, 0x401000);
			program.getMemory().createInitializedBlock(".text", base, 0x1000, (byte) 0x90,
				TaskMonitor.DUMMY, false);

			Address helperEntry = address(program, 0x401100);
			program.getMemory().setBytes(base, MAIN);
			program.getMemory().setBytes(helperEntry, HELPER);

			disassemble(program, base);
			disassemble(program, helperEntry);
			createFunction(program, base, "main");
			createFunction(program, helperEntry, "helper");

			program.getSymbolTable().createLabel(address(program, 0x401200), "a_label",
				SourceType.USER_DEFINED);

			// An overlay block, so tests have a second address space to work with.
			program.getMemory().createInitializedBlock("OVL", address(program, 0x401000), 0x100,
				(byte) 0, TaskMonitor.DUMMY, true);
		}
		finally {
			program.endTransaction(transaction, true);
		}
		return program;
	}

	private static void disassemble(Program program, Address at) {
		new DisassembleCommand(at, null, true).applyTo(program, TaskMonitor.DUMMY);
	}

	private static void createFunction(Program program, Address entry, String name) {
		new CreateFunctionCmd(name, entry, null, SourceType.USER_DEFINED)
				.applyTo(program, TaskMonitor.DUMMY);
	}

	public static Address address(Program program, long offset) {
		return program.getAddressFactory().getDefaultAddressSpace().getAddress(offset);
	}

	/**
	 * Builds a context with the cursor on {@code main}, so scripts that read
	 * {@code ghidra.currentAddress()} have something to work with.
	 */
	public static LuaGhidraContext contextFor(Program program, PrintWriter writer) {
		GhidraState state = new GhidraState(null, null, program, null, null, null);
		state.setCurrentAddress(address(program, 0x401000));
		return LuaGhidraContext.forHost(state,
			new ScriptControls(writer, writer, TaskMonitor.DUMMY));
	}
}
