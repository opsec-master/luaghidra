package luaghidra.bridge;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * Lets Luau code implement Java interfaces.
 *
 * <p>
 * Created from Luau with {@code java.proxy}. Each call is forwarded to the Luau
 * handler registered for the method name, on the interpreter state the proxy was
 * created in.
 *
 * <p>
 * Because a Luau state is single-threaded, a proxy may only be called from the
 * thread running its interpreter. Ghidra APIs that call back synchronously — a
 * {@code Predicate} passed to a query, a {@code Comparator} passed to a sort —
 * are exactly that; one that hands work to a background thread is not, and the
 * call fails with a clear error instead of corrupting the interpreter.
 */
public final class LuaProxy {

	/** Native entry point that dispatches a proxied call into Luau. */
	public interface Dispatcher {
		Object dispatch(long state, long handlerId, String method, Object[] args);
	}

	private static volatile Dispatcher dispatcher;

	private LuaProxy() {
	}

	/**
	 * Installs the dispatcher. Called once by {@link luaghidra.LuauNativeBridge}
	 * so this class does not have to depend on the native bridge directly.
	 */
	public static void setDispatcher(Dispatcher value) {
		dispatcher = value;
	}

	/**
	 * Creates a proxy implementing the named interfaces.
	 *
	 * @param interfaceNames the interfaces to implement
	 * @param state the native interpreter handle the handler lives in
	 * @param handlerId the key of the Luau handler within that interpreter
	 */
	public static Object create(String[] interfaceNames, long state, long handlerId)
			throws ClassNotFoundException {
		Class<?>[] interfaces = new Class<?>[interfaceNames.length];
		for (int i = 0; i < interfaceNames.length; i++) {
			Class<?> type = JavaBridge.forName(interfaceNames[i]);
			if (!type.isInterface()) {
				throw new IllegalArgumentException(
					"java.proxy needs interfaces; " + type.getName() + " is a class");
			}
			interfaces[i] = type;
		}

		ClassLoader loader = interfaces.length > 0 ? interfaces[0].getClassLoader()
				: LuaProxy.class.getClassLoader();
		return Proxy.newProxyInstance(loader, interfaces, new Handler(state, handlerId));
	}

	private record Handler(long state, long handlerId) implements InvocationHandler {

		@Override
		public Object invoke(Object proxy, Method method, Object[] args) {
			// Object's own methods are answered here so a proxy can be printed,
			// compared, and used as a map key without a Luau handler for each.
			String name = method.getName();
			Object[] arguments = args == null ? new Object[0] : args;
			if (method.getDeclaringClass() == Object.class) {
				switch (name) {
					case "hashCode":
						return System.identityHashCode(proxy);
					case "equals":
						return proxy == arguments[0];
					case "toString":
						return "luau proxy@" + Long.toHexString(handlerId);
					default:
						break;
				}
			}

			Dispatcher current = dispatcher;
			if (current == null) {
				throw new IllegalStateException("the Luau proxy dispatcher is not installed");
			}
			Object result = current.dispatch(state, handlerId, name, arguments);
			return JavaBridge.convertArg(result, method.getReturnType());
		}
	}
}
