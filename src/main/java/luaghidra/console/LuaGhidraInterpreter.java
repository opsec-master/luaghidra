package luaghidra.console;

import java.util.List;

import javax.swing.Icon;

import ghidra.app.plugin.core.console.CodeCompletion;
import ghidra.app.plugin.core.interpreter.InterpreterConnection;
import ghidra.app.plugin.core.interpreter.InterpreterConsole;
import ghidra.app.plugin.core.interpreter.InterpreterPanelService;
import ghidra.program.model.listing.Program;
import ghidra.program.util.ProgramLocation;
import ghidra.program.util.ProgramSelection;
import ghidra.util.Disposable;
import luaghidra.LuaGhidraPlugin;

/**
 * Connects a {@link LuaConsole} to a Ghidra interpreter panel and keeps it in
 * step with the tool's current program, cursor, and selection.
 */
public final class LuaGhidraInterpreter implements InterpreterConnection, Disposable {

	private final InterpreterConsole console;
	private final LuaConsole luaConsole;

	public LuaGhidraInterpreter(LuaGhidraPlugin plugin) {
		InterpreterPanelService service =
			plugin.getTool().getService(InterpreterPanelService.class);
		console = service.createInterpreterPanel(this, false);
		luaConsole = new LuaConsole(console, plugin.getTool(),
			plugin.getTool().getProject());
		console.addFirstActivationCallback(luaConsole::restart);
		console.addAction(new ResetAction(luaConsole));
		console.addAction(new CancelAction(luaConsole));
	}

	public void setProgram(Program program) {
		luaConsole.setProgram(program);
	}

	public void setLocation(ProgramLocation location) {
		luaConsole.setLocation(location);
	}

	public void setSelection(ProgramSelection selection) {
		luaConsole.setSelection(selection);
	}

	public void setHighlight(ProgramSelection highlight) {
		luaConsole.setHighlight(highlight);
	}

	@Override
	public String getTitle() {
		return LuaGhidraPlugin.TITLE;
	}

	@Override
	public Icon getIcon() {
		return null;
	}

	@Override
	@Deprecated(since = "the caret-aware overload replaces it")
	public List<CodeCompletion> getCompletions(String cmd) {
		return getCompletions(cmd, cmd.length());
	}

	@Override
	public List<CodeCompletion> getCompletions(String cmd, int caretPos) {
		return luaConsole.complete(cmd, caretPos);
	}

	@Override
	public void dispose() {
		luaConsole.dispose();
		console.dispose();
	}
}
