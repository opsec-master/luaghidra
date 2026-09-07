package luaghidra.console;

import static docking.DockingUtils.CONTROL_KEY_MODIFIER_MASK;

import java.awt.event.KeyEvent;

import javax.swing.ImageIcon;

import docking.ActionContext;
import docking.action.DockingAction;
import docking.action.KeyBindingData;
import docking.action.ToolBarData;
import luaghidra.LuaGhidraPlugin;
import resources.ResourceManager;

/**
 * Toolbar action that resets the Luau interpreter state.
 */
final class ResetAction extends DockingAction {

	private final LuaConsole console;

	ResetAction(LuaConsole console) {
		super("Reset", LuaGhidraPlugin.class.getSimpleName());
		this.console = console;
		setDescription("Reset the interpreter");
		ImageIcon image = ResourceManager.loadImage("images/reload3.png");
		setToolBarData(new ToolBarData(image));
		setEnabled(true);
		setKeyBindingData(new KeyBindingData(KeyEvent.VK_D, CONTROL_KEY_MODIFIER_MASK));
	}

	@Override
	public void actionPerformed(ActionContext context) {
		console.restart();
	}
}
