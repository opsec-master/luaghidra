package luaghidra.console;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.List;

import ghidra.app.plugin.core.console.CodeCompletion;
import ghidra.app.plugin.core.interpreter.InterpreterConsole;
import ghidra.app.script.GhidraState;
import ghidra.app.script.ScriptControls;
import ghidra.framework.model.Project;
import ghidra.framework.plugintool.PluginTool;
import ghidra.program.model.listing.Program;
import ghidra.program.util.ProgramLocation;
import ghidra.program.util.ProgramSelection;
import ghidra.util.Disposable;
import ghidra.util.Msg;
import ghidra.util.task.TaskMonitorAdapter;
import luaghidra.LuaEvalResult;
import luaghidra.runtime.LuaGhidraContext;
import luaghidra.runtime.LuaInterpreter;

/**
 * Drives the read-eval-print loop for the Luau interpreter panel.
 *
 * <p>
 * A single daemon thread reads lines from the console's input stream, feeds them
 * to a persistent interpreter, and writes captured output back to the console.
 * Multi-line statements are supported through continuation: when the evaluator
 * reports that the accumulated input is syntactically incomplete, the prompt
 * switches to a continuation prompt until the statement is complete.
 *
 * <p>
 * The console tracks the tool's current program, cursor, and selection, so
 * {@code require("@ghidra")} sees the same state a script would.
 */
public final class LuaConsole implements Disposable {

	private static final String PRIMARY_PROMPT = "lua> ";
	private static final String CONTINUE_PROMPT = "  .. ";

	private final InterpreterConsole console;
	private final BufferedReader inputReader;
	private final PrintWriter out;
	private final PrintWriter err;
	private final StringBuilder pending = new StringBuilder();
	private final Object lock = new Object();
	private final GhidraState state;
	private final TaskMonitorAdapter monitor = new TaskMonitorAdapter(true);

	private volatile boolean disposed;
	private LuaInterpreter interpreter;
	private Thread thread;

	public LuaConsole(InterpreterConsole console, PluginTool tool, Project project) {
		this.console = console;
		this.inputReader =
			new BufferedReader(new InputStreamReader(console.getStdin(), StandardCharsets.UTF_8));
		this.out = console.getOutWriter();
		this.err = console.getErrWriter();
		// The copy constructor yields a non-global state: it tracks the tool's
		// program, cursor, and selection without re-firing plugin events back
		// into the tool (which would echo every navigation, and throws when the
		// tool clears the location on close).
		this.state = new GhidraState(new GhidraState(tool, project, null, null, null, null));
	}

	/** Points the console at the tool's active program. */
	public void setProgram(Program program) {
		state.setCurrentProgram(program);
	}

	/** Points the console at the listing cursor. */
	public void setLocation(ProgramLocation location) {
		state.setCurrentLocation(location);
	}

	/** Points the console at the listing selection. */
	public void setSelection(ProgramSelection selection) {
		state.setCurrentSelection(selection);
	}

	/** Points the console at the listing highlight. */
	public void setHighlight(ProgramSelection highlight) {
		state.setCurrentHighlight(highlight);
	}

	/** Completion candidates for the console's input line. */
	public List<CodeCompletion> complete(String command, int caretPos) {
		LuaInterpreter current;
		synchronized (lock) {
			current = interpreter;
		}
		return LuaCompletions.compute(current, command, caretPos);
	}

	/** Cancels the command currently being evaluated, if any. */
	public void cancel() {
		monitor.cancel();
	}

	/**
	 * (Re)initializes the interpreter and starts the read loop if needed.
	 */
	public void restart() {
		synchronized (lock) {
			if (disposed) {
				return;
			}
			closeInterpreter();
			pending.setLength(0);
			console.clear();

			try {
				interpreter = LuaInterpreter.create();
			}
			catch (Throwable t) {
				Msg.error(this, "Failed to create the Luau interpreter", t);
				err.println("Failed to create the Luau interpreter: " + t.getMessage());
				err.flush();
				console.setInputPermitted(false);
				return;
			}

			interpreter.setContext(
				LuaGhidraContext.forHost(state, new ScriptControls(console, monitor)));

			out.println(banner());
			out.flush();
			console.setPrompt(PRIMARY_PROMPT);

			if (thread == null) {
				thread = new Thread(this::readLoop, "LuaGhidra Interpreter");
				thread.setDaemon(true);
				thread.start();
			}
		}
	}

	private String banner() {
		return "Luau interpreter — require(\"@ghidra\") for the scripting API, "
				+ "java.import(...) for anything else";
	}

	private void readLoop() {
		while (!disposed) {
			String line;
			try {
				line = inputReader.readLine();
			}
			catch (IOException e) {
				break;
			}
			if (line == null) {
				if (disposed) {
					break;
				}
				continue;
			}
			try {
				process(line);
			}
			catch (Throwable t) {
				Msg.error(this, "Unexpected error in Luau interpreter", t);
				err.println("Internal error: " + t.getMessage());
				err.flush();
				resetPending();
			}
		}
	}

	private void process(String line) {
		if (pending.length() > 0) {
			pending.append('\n');
		}
		pending.append(line);

		LuaInterpreter current;
		synchronized (lock) {
			current = interpreter;
		}
		if (current == null) {
			return;
		}

		monitor.clearCancelled();
		LuaEvalResult result = current.eval(pending.toString());
		if (result.isIncomplete()) {
			console.setPrompt(CONTINUE_PROMPT);
			return;
		}

		if (result.hasOutput()) {
			out.print(result.output());
			out.flush();
		}
		if (result.isError()) {
			err.println(result.message());
			err.flush();
		}
		resetPending();
	}

	private void resetPending() {
		pending.setLength(0);
		console.setPrompt(PRIMARY_PROMPT);
	}

	@Override
	public void dispose() {
		disposed = true;
		monitor.cancel();
		try {
			console.getStdin().close();
		}
		catch (IOException ignored) {
			// closing stdin only serves to unblock the read loop
		}

		Thread current;
		synchronized (lock) {
			current = thread;
		}
		if (current != null) {
			current.interrupt();
			try {
				current.join(1000);
			}
			catch (InterruptedException ignored) {
				Thread.currentThread().interrupt();
			}
		}

		synchronized (lock) {
			closeInterpreter();
			thread = null;
		}
	}

	private void closeInterpreter() {
		if (interpreter != null) {
			interpreter.close();
			interpreter = null;
		}
	}
}
