package luaghidra.console;

import javax.swing.ImageIcon;

import docking.ActionContext;
import docking.action.DockingAction;
import docking.action.ToolBarData;
import luaghidra.LuaGhidraPlugin;
import resources.ResourceManager;

/**
 * Toolbar action that cancels the command the interpreter is running.
 *
 * <p>
 * Cancellation goes through the task monitor scripts observe, so loops written
 * with the {@code @ghidra} iterators or {@code ghidra.checkCancelled()} stop at
 * their next step. A command that never checks the monitor runs to completion.
 */
final class CancelAction extends DockingAction {

	private final LuaConsole console;

	CancelAction(LuaConsole console) {
		super("Cancel", LuaGhidraPlugin.class.getSimpleName());
		this.console = console;
		setDescription("Cancel the running command");
		ImageIcon image = ResourceManager.loadImage("images/process-stop.png");
		setToolBarData(new ToolBarData(image));
		setEnabled(true);
	}

	@Override
	public void actionPerformed(ActionContext context) {
		console.cancel();
	}
}
