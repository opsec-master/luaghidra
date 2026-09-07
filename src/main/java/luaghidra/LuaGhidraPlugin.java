package luaghidra;

import ghidra.app.CorePluginPackage;
import ghidra.app.plugin.PluginCategoryNames;
import ghidra.app.plugin.ProgramPlugin;
import ghidra.app.plugin.core.interpreter.InterpreterPanelService;
import ghidra.framework.plugintool.PluginInfo;
import ghidra.framework.plugintool.PluginTool;
import ghidra.framework.plugintool.util.PluginStatus;
import ghidra.program.model.listing.Program;
import ghidra.program.util.ProgramLocation;
import ghidra.program.util.ProgramSelection;
import luaghidra.console.LuaGhidraInterpreter;

/**
 * Provides an interactive Luau interpreter console inside Ghidra.
 */
//@formatter:off
@PluginInfo(
	status = PluginStatus.STABLE,
	packageName = CorePluginPackage.NAME,
	category = PluginCategoryNames.COMMON,
	shortDescription = "LuaGhidra Interpreter",
	description = "Provides an interactive Luau interpreter console and the .luau script API.",
	servicesRequired = { InterpreterPanelService.class }
)
//@formatter:on
public class LuaGhidraPlugin extends ProgramPlugin {

	public static final String TITLE = "LuaGhidra";

	private LuaGhidraInterpreter interpreter;

	public LuaGhidraPlugin(PluginTool tool) {
		super(tool);
	}

	@Override
	protected void init() {
		super.init();
		interpreter = new LuaGhidraInterpreter(this);
	}

	@Override
	protected void programActivated(Program program) {
		if (interpreter != null) {
			interpreter.setProgram(program);
		}
	}

	@Override
	protected void programDeactivated(Program program) {
		if (interpreter != null) {
			interpreter.setProgram(null);
		}
	}

	@Override
	protected void locationChanged(ProgramLocation location) {
		if (interpreter != null) {
			interpreter.setLocation(location);
		}
	}

	@Override
	protected void selectionChanged(ProgramSelection selection) {
		if (interpreter != null) {
			interpreter.setSelection(selection);
		}
	}

	@Override
	protected void highlightChanged(ProgramSelection highlight) {
		if (interpreter != null) {
			interpreter.setHighlight(highlight);
		}
	}

	@Override
	protected void dispose() {
		if (interpreter != null) {
			interpreter.dispose();
			interpreter = null;
		}
		super.dispose();
	}
}
