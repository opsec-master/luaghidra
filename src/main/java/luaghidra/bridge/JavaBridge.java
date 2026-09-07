package luaghidra.bridge;

import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Reflection back-end for the Luau {@code java} module.
 *
 * <p>
 * This is a port of the {@code java} library from the
 * {@code party.iroiro.luajava} project, adapted for the Luau VM used by this
 * extension. The original implementation has the Java side reach directly into
 * the Lua stack through a large JNI surface. Here the native bridge performs all
 * Lua&lt;-&gt;Java primitive conversion and calls into this class with plain
 * {@link Object} values, so this class only deals with reflection.
 *
 * <p>
 * All methods are invoked from native code (see {@code src/main/native/java_bridge.cpp}).
 * Methods return {@link #NOT_FOUND} or {@link #VOID} sentinels rather than
 * throwing for control-flow cases the native side needs to distinguish.
 */
public final class JavaBridge {

	/** Returned by field lookups when no such field exists. */
	public static final Object NOT_FOUND = new Object();

	/** Returned by method invocations when the Java method is {@code void}. */
	public static final Object VOID = new Object();

	/**
	 * Returned by member lookups when the name resolves to a method rather than a
	 * field. The native bridge turns this into a bound-call closure.
	 */
	public static final Object METHOD = new Object();

	private JavaBridge() {
	}

	public static Object sentinelNotFound() {
		return NOT_FOUND;
	}

	public static Object sentinelVoid() {
		return VOID;
	}

	public static Object sentinelMethod() {
		return METHOD;
	}

	// --- Lua type codes returned by luaType, mirrored in the native bridge ---
	private static final int TYPE_NULL = 0;
	private static final int TYPE_BOOLEAN = 1;
	private static final int TYPE_LONG = 2;
	private static final int TYPE_DOUBLE = 3;
	private static final int TYPE_STRING = 4;
	// Code 5 (class) is reserved on the native side but never produced here;
	// java.lang.Class instances are returned as TYPE_OBJECT.
	private static final int TYPE_ARRAY = 6;
	private static final int TYPE_OBJECT = 7;

	/**
	 * Classifies a Java value so the native bridge can decide how to push it.
	 */
	public static int luaType(Object value) {
		if (value == null) {
			return TYPE_NULL;
		}
		if (value instanceof Boolean) {
			return TYPE_BOOLEAN;
		}
		if (value instanceof Character) {
			return TYPE_LONG;
		}
		if (value instanceof Byte || value instanceof Short || value instanceof Integer
				|| value instanceof Long) {
			return TYPE_LONG;
		}
		if (value instanceof Float || value instanceof Double) {
			return TYPE_DOUBLE;
		}
		if (value instanceof String) {
			return TYPE_STRING;
		}
		// A java.lang.Class instance obtained from a method (e.g. getClass()) is
		// exposed as a jobject so its instance methods work. The jclass type is
		// reserved for java.import / inner-class lookups (static access).
		if (value.getClass().isArray()) {
			return TYPE_ARRAY;
		}
		return TYPE_OBJECT;
	}

	public static boolean asBoolean(Object value) {
		return (Boolean) value;
	}

	public static long asLong(Object value) {
		if (value instanceof Character) {
			return (char) (Character) value;
		}
		return ((Number) value).longValue();
	}

	public static double asDouble(Object value) {
		return ((Number) value).doubleValue();
	}

	public static String asString(Object value) {
		return (String) value;
	}

	/**
	 * Value equality for the {@code __eq} metamethod.
	 *
	 * <p>
	 * Without this, two Lua references to the same Java object compare unequal,
	 * because each one is a distinct userdata. Ghidra hands back a fresh instance
	 * on almost every call, so identity comparison would make
	 * {@code func.entry == someAddress} answer false for equal addresses.
	 */
	public static boolean valuesEqual(Object a, Object b) {
		if (a == b) {
			return true;
		}
		if (a == null || b == null) {
			return false;
		}
		return a.equals(b);
	}

	/**
	 * Ordering for the {@code __lt} and {@code __le} metamethods, so that
	 * {@link Comparable} values — addresses above all — can be compared with
	 * {@code <} and {@code <=}.
	 *
	 * @throws RuntimeException when the values are not mutually comparable
	 */
	public static int compare(Object a, Object b) {
		if (!(a instanceof Comparable<?>)) {
			throw new RuntimeException(className(a) + " values cannot be ordered");
		}
		try {
			@SuppressWarnings("unchecked")
			Comparable<Object> left = (Comparable<Object>) a;
			return left.compareTo(b);
		}
		catch (ClassCastException e) {
			throw new RuntimeException(
				"cannot compare " + className(a) + " with " + className(b));
		}
	}

	public static String display(Object value) {
		if (value == null) {
			return "null";
		}
		try {
			return String.valueOf(value);
		}
		catch (Throwable t) {
			return value.getClass().getName() + "@<toString failed>";
		}
	}

	// --- Boxing helpers used by the native side to build argument arrays ---
	public static Object box(long value) {
		return value;
	}

	public static Object box(double value) {
		return value;
	}

	public static Object box(boolean value) {
		return value;
	}

	// --- Class / field / method operations ---

	public static Object importClass(String name) throws ClassNotFoundException {
		return forName(name);
	}

	public static Object importInner(Object owner, String name) {
		if (!(owner instanceof Class)) {
			return NOT_FOUND;
		}
		try {
			return forName(((Class<?>) owner).getName() + '$' + name);
		}
		catch (ClassNotFoundException e) {
			return NOT_FOUND;
		}
	}

	public static Object getStaticField(Object owner, String name) {
		Class<?> clazz = (Class<?>) owner;
		Field field = findField(clazz, name);
		if (field == null || !Modifier.isStatic(field.getModifiers())) {
			return NOT_FOUND;
		}
		try {
			return field.get(null);
		}
		catch (IllegalAccessException e) {
			throw new RuntimeException("cannot read static field " + name + ": " + e.getMessage(), e);
		}
	}

	public static void setStaticField(Object owner, String name, Object value) {
		Class<?> clazz = (Class<?>) owner;
		Field field = findField(clazz, name);
		if (field == null || !Modifier.isStatic(field.getModifiers())) {
			throw new RuntimeException("no static field '" + name + "' on " + clazz.getName());
		}
		try {
			field.set(null, convertArg(value, field.getType()));
		}
		catch (IllegalAccessException e) {
			throw new RuntimeException("cannot write static field " + name + ": " + e.getMessage(), e);
		}
	}

	public static Object getField(Object target, String name) {
		Field field = findField(target.getClass(), name);
		if (field == null) {
			return NOT_FOUND;
		}
		try {
			return field.get(target);
		}
		catch (IllegalAccessException e) {
			throw new RuntimeException("cannot read field " + name + ": " + e.getMessage(), e);
		}
	}

	/**
	 * Writes an instance field if one exists.
	 *
	 * @return {@code false} when the class has no such field, letting the caller
	 *         fall back to a registered Luau extension property
	 */
	public static boolean trySetField(Object target, String name, Object value) {
		Field field = findField(target.getClass(), name);
		if (field == null) {
			return false;
		}
		try {
			field.set(target, convertArg(value, field.getType()));
			return true;
		}
		catch (IllegalAccessException e) {
			throw new RuntimeException("cannot write field " + name + ": " + e.getMessage(), e);
		}
	}

	public static void setField(Object target, String name, Object value) {
		Field field = findField(target.getClass(), name);
		if (field == null) {
			throw new RuntimeException("no field '" + name + "' on " + target.getClass().getName());
		}
		try {
			field.set(target, convertArg(value, field.getType()));
		}
		catch (IllegalAccessException e) {
			throw new RuntimeException("cannot write field " + name + ": " + e.getMessage(), e);
		}
	}

	/**
	 * Invokes a method, resolving overloads against the supplied arguments.
	 *
	 * @param self the receiver, or {@code null} for a static call
	 * @param clazz the declaring class for a static call, or {@code null} to use
	 *            {@code self.getClass()}
	 * @param name the method name
	 * @param args the already-converted arguments
	 * @return the result, {@link #VOID} for void methods
	 */
	public static Object invokeMethod(Object self, Object clazz, String name, Object[] args) {
		Class<?> target = clazz != null ? (Class<?>) clazz
				: (self != null ? self.getClass() : null);
		if (target == null) {
			throw new RuntimeException("cannot resolve class for method '" + name + "'");
		}
		Object[] converted = new Object[args.length];
		Method method = matchMethod(target, name, args, converted);
		if (method == null) {
			throw new RuntimeException(noMethodMessage(target, name, args));
		}
		method = accessible(target, method);
		try {
			Object result = method.invoke(Modifier.isStatic(method.getModifiers()) ? null : self,
				converted);
			return method.getReturnType() == void.class ? VOID : result;
		}
		catch (IllegalAccessException e) {
			throw new RuntimeException("cannot invoke " + name + ": " + e.getMessage(), e);
		}
		catch (InvocationTargetException e) {
			throw sneakyThrow(e.getCause() != null ? e.getCause() : e);
		}
	}

	public static Object construct(Object clazz, Object[] args) {
		if (!(clazz instanceof Class)) {
			throw new RuntimeException("java.new expects a class");
		}
		Class<?> target = (Class<?>) clazz;
		if (target.isInterface() || Modifier.isAbstract(target.getModifiers())) {
			throw new RuntimeException("cannot instantiate " + target.getName());
		}
		Object[] converted = new Object[args.length];
		Constructor<?> constructor = matchConstructor(target, args, converted);
		if (constructor == null) {
			throw new RuntimeException("no matching constructor for " + target.getName()
					+ " with " + args.length + " argument(s)");
		}
		try {
			if (!constructor.canAccess(null)) {
				constructor.setAccessible(true);
			}
			return constructor.newInstance(converted);
		}
		catch (InstantiationException | IllegalAccessException e) {
			throw new RuntimeException("cannot construct " + target.getName() + ": " + e.getMessage(),
				e);
		}
		catch (InvocationTargetException e) {
			throw sneakyThrow(e.getCause() != null ? e.getCause() : e);
		}
	}

	public static Object newArray(Object componentType, int length) {
		if (!(componentType instanceof Class)) {
			throw new RuntimeException("java.array expects a class component type");
		}
		return Array.newInstance((Class<?>) componentType, length);
	}

	/**
	 * Reads an array element using a 1-based (Lua) index.
	 *
	 * @return the element (boxed for primitive component types)
	 */
	public static Object arrayGet(Object array, int luaIndex) {
		int i = luaIndex - 1;
		int length = Array.getLength(array);
		if (i < 0 || i >= length) {
			throw new RuntimeException(
				"array index " + luaIndex + " out of bounds (length " + length + ")");
		}
		return Array.get(array, i);
	}

	/**
	 * Writes an array element using a 1-based (Lua) index.
	 */
	public static void arraySet(Object array, int luaIndex, Object value) {
		int i = luaIndex - 1;
		int length = Array.getLength(array);
		if (i < 0 || i >= length) {
			throw new RuntimeException(
				"array index " + luaIndex + " out of bounds (length " + length + ")");
		}
		Array.set(array, i, convertArg(value, array.getClass().getComponentType()));
	}

	public static int arrayLength(Object array) {
		return Array.getLength(array);
	}

	// --- Member introspection (used for Luau extension dispatch) ---

	private static final Map<Class<?>, Set<String>> METHOD_NAMES = new ConcurrentHashMap<>();
	private static final Map<String, String[]> TYPE_NAMES = new ConcurrentHashMap<>();

	/**
	 * Returns the runtime class name of a value, used as the extension-registry
	 * lookup key on the native side.
	 */
	public static String className(Object value) {
		return value == null ? "null" : value.getClass().getName();
	}

	/**
	 * Returns the name of the class a value represents: a {@link Class}'s own
	 * name, or the runtime class name of anything else.
	 */
	public static String declaredClassName(Object value) {
		return value instanceof Class<?> clazz ? clazz.getName() : className(value);
	}

	/**
	 * Resolves {@code name} against an instance in a single call.
	 *
	 * @return the field value, {@link #METHOD} when the name is a method, or
	 *         {@link #NOT_FOUND} when the class has neither
	 */
	public static Object getMember(Object target, String name) {
		Field field = findField(target.getClass(), name);
		if (field != null) {
			try {
				return field.get(target);
			}
			catch (IllegalAccessException e) {
				throw new RuntimeException(
					"cannot read field " + name + ": " + e.getMessage(), e);
			}
		}
		return methodNames(target.getClass()).contains(name) ? METHOD : NOT_FOUND;
	}

	/**
	 * Static counterpart of {@link #getMember(Object, String)}. Inner-class lookup
	 * stays on the native side because it produces a {@code jclass} rather than a
	 * plain value.
	 */
	public static Object getStaticMember(Object owner, String name) {
		Class<?> clazz = (Class<?>) owner;
		Field field = findField(clazz, name);
		if (field != null && Modifier.isStatic(field.getModifiers())) {
			try {
				return field.get(null);
			}
			catch (IllegalAccessException e) {
				throw new RuntimeException(
					"cannot read static field " + name + ": " + e.getMessage(), e);
			}
		}
		return methodNames(clazz).contains(name) ? METHOD : NOT_FOUND;
	}

	/**
	 * Returns {@code true} when the receiver's class has a public method called
	 * {@code name}. Used by the native namecall path to decide between a Java
	 * method and a registered Luau extension method.
	 */
	public static boolean hasMethod(Object target, String name) {
		return target != null && methodNames(target.getClass()).contains(name);
	}

	/**
	 * Returns {@code true} when {@code className} declares or inherits a public
	 * field or method called {@code name}. Used to reject Luau extensions that
	 * would shadow a Java member.
	 */
	public static boolean hasMember(String className, String name) {
		Class<?> clazz;
		try {
			clazz = forName(className);
		}
		catch (ClassNotFoundException e) {
			return false;
		}
		if (methodNames(clazz).contains(name)) {
			return true;
		}
		return findField(clazz, name) != null;
	}

	/**
	 * Returns the assignability chain of a class: the class itself, its
	 * superclasses, and every interface it implements, most derived first.
	 *
	 * <p>
	 * The native bridge walks this list to merge the registered Luau extension
	 * tables for a value into one flat lookup table.
	 */
	public static String[] typeNames(String className) {
		String[] cached = TYPE_NAMES.get(className);
		if (cached != null) {
			return cached;
		}
		Set<String> names = new LinkedHashSet<>();
		try {
			collectTypeNames(forName(className), names);
		}
		catch (ClassNotFoundException e) {
			names.add(className);
		}
		String[] result = names.toArray(new String[0]);
		TYPE_NAMES.put(className, result);
		return result;
	}

	private static void collectTypeNames(Class<?> clazz, Set<String> out) {
		for (Class<?> c = clazz; c != null; c = c.getSuperclass()) {
			out.add(c.getName());
			collectInterfaces(c, out);
		}
	}

	private static void collectInterfaces(Class<?> clazz, Set<String> out) {
		for (Class<?> i : clazz.getInterfaces()) {
			if (out.add(i.getName())) {
				collectInterfaces(i, out);
			}
		}
	}

	private static final Map<Class<?>, Map<Method, Method>> ACCESSIBLE = new ConcurrentHashMap<>();

	/**
	 * Re-resolves a method against a publicly accessible supertype.
	 *
	 * <p>
	 * Reflection resolves methods against a value's runtime class, which is often
	 * a package-private or non-exported implementation class — Ghidra returns
	 * plenty of these, as does the JDK ({@code HashMap$KeyIterator}, for
	 * instance). Invoking such a {@code Method} fails even though the method is
	 * public, because the declaring class is not accessible to this module.
	 * Looking the same signature up on a public superclass or interface produces a
	 * {@code Method} that invokes cleanly.
	 *
	 * <p>
	 * The search starts at the receiver's class rather than the declaring class,
	 * because the public interface is frequently implemented by a subclass of
	 * whichever class declares the method.
	 *
	 * @param receiver the class the call is made on
	 * @param method the method resolved from {@code receiver}
	 */
	private static Method accessible(Class<?> receiver, Method method) {
		Map<Method, Method> perReceiver =
			ACCESSIBLE.computeIfAbsent(receiver, key -> new ConcurrentHashMap<>());
		Method cached = perReceiver.get(method);
		if (cached != null) {
			return cached;
		}

		Method resolved = method;
		if (!isAccessibleType(method.getDeclaringClass())) {
			Method found =
				findAccessible(receiver, method.getName(), method.getParameterTypes());
			if (found != null) {
				resolved = found;
			}
			else {
				try {
					method.setAccessible(true);
				}
				catch (RuntimeException ignored) {
					// invoke() will surface the access error with more context
				}
			}
		}
		perReceiver.put(method, resolved);
		return resolved;
	}

	private static Method findAccessible(Class<?> start, String name, Class<?>[] parameterTypes) {
		for (Class<?> clazz = start; clazz != null; clazz = clazz.getSuperclass()) {
			Method found = declaredPublic(clazz, name, parameterTypes);
			if (found != null) {
				return found;
			}
			for (Class<?> iface : clazz.getInterfaces()) {
				found = findAccessible(iface, name, parameterTypes);
				if (found != null) {
					return found;
				}
			}
		}
		return null;
	}

	private static Method declaredPublic(Class<?> clazz, String name, Class<?>[] parameterTypes) {
		if (!isAccessibleType(clazz)) {
			return null;
		}
		try {
			Method method = clazz.getMethod(name, parameterTypes);
			return isAccessibleType(method.getDeclaringClass()) ? method : null;
		}
		catch (NoSuchMethodException e) {
			return null;
		}
	}

	private static boolean isAccessibleType(Class<?> clazz) {
		if (!Modifier.isPublic(clazz.getModifiers())) {
			return false;
		}
		Module module = clazz.getModule();
		return module == null || !module.isNamed()
				|| module.isExported(clazz.getPackageName(), JavaBridge.class.getModule());
	}

	private static Set<String> methodNames(Class<?> clazz) {
		Set<String> cached = METHOD_NAMES.get(clazz);
		if (cached != null) {
			return cached;
		}
		Set<String> names = new LinkedHashSet<>();
		for (Method method : clazz.getMethods()) {
			names.add(method.getName());
		}
		METHOD_NAMES.put(clazz, names);
		return names;
	}

	/**
	 * Returns every public method name on a class, sorted. Used by the console's
	 * code completion.
	 */
	public static String[] memberNames(String className) {
		Class<?> clazz;
		try {
			clazz = forName(className);
		}
		catch (ClassNotFoundException e) {
			return new String[0];
		}
		Set<String> names = new LinkedHashSet<>(methodNames(clazz));
		for (Field field : clazz.getFields()) {
			names.add(field.getName());
		}
		String[] result = names.toArray(new String[0]);
		Arrays.sort(result);
		return result;
	}

	// --- internals ---

	/**
	 * Rethrows a {@link Throwable} (including the original cause of a reflective
	 * call) without wrapping, so the native bridge captures the real exception
	 * for {@code java.caught()}. The declared return type lets callers write
	 * {@code throw sneakyThrow(t);} for definite-assignment purposes.
	 */
	@SuppressWarnings("unchecked")
	private static <T extends Throwable> RuntimeException sneakyThrow(Throwable t) throws T {
		throw (T) t;
	}

	static Class<?> forName(String name) throws ClassNotFoundException {
		switch (name) {
			case "boolean":
				return boolean.class;
			case "byte":
				return byte.class;
			case "char":
				return char.class;
			case "short":
				return short.class;
			case "int":
				return int.class;
			case "long":
				return long.class;
			case "float":
				return float.class;
			case "double":
				return double.class;
			case "void":
				return void.class;
			default:
				return Class.forName(name, true, classLoader());
		}
	}

	private static ClassLoader classLoader() {
		ClassLoader loader = Thread.currentThread().getContextClassLoader();
		if (loader != null) {
			return loader;
		}
		return JavaBridge.class.getClassLoader();
	}

	private static Field findField(Class<?> clazz, String name) {
		try {
			return clazz.getField(name);
		}
		catch (NoSuchFieldException e) {
			return null;
		}
	}

	private static String noMethodMessage(Class<?> clazz, String name, Object[] args) {
		StringBuilder sb = new StringBuilder("no matching method ").append(clazz.getName())
				.append('.').append(name).append('(');
		for (int i = 0; i < args.length; i++) {
			if (i > 0) {
				sb.append(", ");
			}
			sb.append(args[i] == null ? "nil" : args[i].getClass().getName());
		}
		return sb.append(')').toString();
	}

	private static Method matchMethod(Class<?> clazz, String name, Object[] args, Object[] out) {
		List<Method> candidates = new ArrayList<>();
		for (Method method : clazz.getMethods()) {
			if (method.getName().equals(name) && method.getParameterCount() == args.length) {
				candidates.add(method);
			}
		}
		for (Method method : candidates) {
			if (tryConvert(method.getParameterTypes(), args, out)) {
				return method;
			}
		}
		return null;
	}

	private static Constructor<?> matchConstructor(Class<?> clazz, Object[] args, Object[] out) {
		for (Constructor<?> constructor : clazz.getConstructors()) {
			if (constructor.getParameterCount() == args.length
					&& tryConvert(constructor.getParameterTypes(), args, out)) {
				return constructor;
			}
		}
		return null;
	}

	private static boolean tryConvert(Class<?>[] types, Object[] args, Object[] out) {
		for (int i = 0; i < types.length; i++) {
			try {
				out[i] = convertArg(args[i], types[i]);
			}
			catch (IllegalArgumentException e) {
				return false;
			}
		}
		return true;
	}

	/**
	 * Converts a single argument to the requested parameter type.
	 *
	 * @throws IllegalArgumentException when the value cannot satisfy the type
	 */
	static Object convertArg(Object value, Class<?> type) {
		if (type == void.class || type == Void.class) {
			return null;
		}
		if (value == null) {
			if (type.isPrimitive()) {
				throw new IllegalArgumentException("null for primitive " + type);
			}
			return null;
		}
		if (type == Object.class) {
			return value;
		}
		if (type.isInstance(value) && !(value instanceof Number && isNumeric(type))) {
			return value;
		}
		if (value instanceof Boolean) {
			if (type == boolean.class || type == Boolean.class) {
				return value;
			}
		}
		else if (value instanceof Character) {
			if (type == char.class || type == Character.class) {
				return value;
			}
			if (isNumeric(type)) {
				return convertNumber((int) (char) (Character) value, type);
			}
		}
		else if (value instanceof Number) {
			if (isNumeric(type)) {
				return convertNumber((Number) value, type);
			}
			if (type == char.class || type == Character.class) {
				return (char) ((Number) value).intValue();
			}
			if (type == boolean.class || type == Boolean.class) {
				return ((Number) value).doubleValue() != 0;
			}
		}
		else if (value instanceof String) {
			String s = (String) value;
			if (type == String.class || type == CharSequence.class) {
				return s;
			}
			if ((type == char.class || type == Character.class) && s.length() == 1) {
				return s.charAt(0);
			}
		}
		if (type.isInstance(value)) {
			return value;
		}
		throw new IllegalArgumentException("cannot convert " + value.getClass().getName()
				+ " to " + type.getName());
	}

	private static boolean isNumeric(Class<?> type) {
		return type == byte.class || type == Byte.class
				|| type == short.class || type == Short.class
				|| type == int.class || type == Integer.class
				|| type == long.class || type == Long.class
				|| type == float.class || type == Float.class
				|| type == double.class || type == Double.class
				|| type == Number.class;
	}

	private static Object convertNumber(Number n, Class<?> type) {
		if (type == byte.class || type == Byte.class) {
			return n.byteValue();
		}
		if (type == short.class || type == Short.class) {
			return n.shortValue();
		}
		if (type == int.class || type == Integer.class) {
			return n.intValue();
		}
		if (type == long.class || type == Long.class) {
			return n.longValue();
		}
		if (type == float.class || type == Float.class) {
			return n.floatValue();
		}
		if (type == double.class || type == Double.class || type == Number.class) {
			return n.doubleValue();
		}
		throw new IllegalArgumentException("not a numeric type: " + type);
	}
}
