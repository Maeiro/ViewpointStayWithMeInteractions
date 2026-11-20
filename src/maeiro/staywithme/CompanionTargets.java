package maeiro.staywithme;

import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;

public final class CompanionTargets {
    private static final String TAG = "[Stay With Me Viewpoint Interactions] ";
    private static final String NAMESPACE = "viewpoint.interact.";
    private static final Map<String, String> SUPPORTED = Map.of(
            "LootTargets", "8a87a04996c804971503413b1f40199fe1fb43fda7834117c40ff7c94d098c57",
            "LootTargets$Target", "e16d1b36fd2132e22422faa4eb93f81dce99416d49b72bd8de002f4dddffab19",
            "LootBoxes", "fa8987203f2cb800092edda1213ad1df7bde8c7def51cee7a0d57ffab979dfb0",
            "LootRows", "d1c10a26c0de6a53e5781ef1e3e2c56001eb1002a7143400766979772397bc0b",
            "LootActions", "a093c2b95f8fc537abad0ce63cdc98205416ee6e0ee368f25c55385e62fb4bb1",
            "InteractActions", "b281727830e20a9eea9f8ad5e2da38ee03ee2a205b1e59bc12f23e1949ddc97d");

    private static final int PERSON = 6;
    private static final int REACH = 2;
    private static final float HALF_WIDTH = 0.3f;
    private static final float HEIGHT = 1.6f;
    private static final float FLOOR_HEIGHT = (float) Math.sqrt(6);
    private static Binding binding;
    private static boolean attempted;

    private CompanionTargets() {}

    public static void addCandidate(IsoPlayer player, IsoGridSquare here) {
        KahluaTable client = readyClient();
        if (client == null || player != IsoPlayer.players[0]) return;
        Binding api = binding();
        if (api == null) return;
        client.rawset("nativeCandidateHook", Boolean.TRUE);

        // Viewpoint already handles companions using an IsoPlayer body.
        if (!(companion() instanceof IsoZombie body) || body.isDead()) return;
        IsoGridSquare square = body.getCurrentSquare();
        if (square == null || here == null || square.getZ() != here.getZ()
                || Math.abs(square.getX() - here.getX()) > REACH
                || Math.abs(square.getY() - here.getY()) > REACH || !player.CanSee(body)) return;

        float x = body.getX();
        float y = body.getY();
        float z = body.getZ() * FLOOR_HEIGHT;
        if (!Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z)) return;
        try {
            int index = (int) api.add.invoke(null, PERSON, null, body);
            api.grow.invoke(null, index, x - HALF_WIDTH, y - HALF_WIDTH, z,
                    x + HALF_WIDTH, y + HALF_WIDTH, z + HEIGHT);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
            fail(client, error);
        }
    }

    public static void recordTarget(IsoPlayer player, Object target) {
        KahluaTable client = readyClient();
        if (client == null || player != IsoPlayer.players[0] || binding == null
                || client.rawget("nativeCandidateHook") != Boolean.TRUE) return;
        try {
            IsoGameCharacter body = companion();
            Object selected = target != null && body != null && binding.object.get(target) == body ? body : null;
            if (client.rawget("nativeBody") != selected) {
                client.rawset("nativeBody", selected);
                client.rawset("nativePath", null);
            }
        } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
            fail(client, error);
        }
    }

    public static String harvestFunction(String function, Object[] arguments) {
        if (arguments == null || arguments.length != 2 || arguments[1] == null || binding == null) return function;
        KahluaTable client = null;
        try {
            client = readyClient();
            if (client == null || client.rawget("nativeBody") != arguments[1] || companion() != arguments[1]) {
                return function;
            }
            if (client.rawget("nativeActive") != Boolean.TRUE) {
                client.rawset("nativeActive", Boolean.TRUE);
                System.out.println(TAG + "Native interaction panel active");
            }
            return "ViewpointStayWithMeInteractionsClient.nativeHarvest";
        } catch (RuntimeException | LinkageError error) {
            if (client != null) fail(client, error);
            return function;
        }
    }

    public static int wrapSelection(Object rows, int from, int direction) {
        KahluaTable client = readyClient();
        Binding api = binding;
        if (client == null || api == null || client.rawget("nativeActive") != Boolean.TRUE
                || client.rawget("nativeBody") == null) return -1;
        try {
            int count = ((List<?>) api.rows.get(rows)).size();
            // Boundary indices also prevent recursion through the patched method.
            if (from < 0 || from >= count) return -1;
            return (int) api.nextSelectable.invoke(rows, direction < 0 ? count : -1, direction);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
            fail(client, error);
            return -1;
        }
    }

    private static KahluaTable readyClient() {
        Object value = LuaManager.env == null ? null : LuaManager.env.rawget("ViewpointStayWithMeInteractionsClient");
        return value instanceof KahluaTable client && client.rawget("nativeMenuReady") == Boolean.TRUE ? client : null;
    }

    private static IsoGameCharacter companion() {
        Object value = LuaManager.env.rawget("Bridge");
        return value instanceof KahluaTable bridge && bridge.rawget("body") instanceof IsoGameCharacter body ? body : null;
    }

    private static Binding binding() {
        if (attempted) return binding;
        attempted = true;
        try {
            ClassLoader loader = CompanionTargets.class.getClassLoader();
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            for (var entry : SUPPORTED.entrySet()) {
                String name = NAMESPACE + entry.getKey();
                try (InputStream bytes = loader.getResourceAsStream(name.replace('.', '/') + ".class")) {
                    if (bytes == null || !entry.getValue().equals(HexFormat.of().formatHex(digest.digest(bytes.readAllBytes())))) {
                        throw new IOException("Unrecognized Viewpoint class " + name);
                    }
                }
            }
            Class<?> targets = Class.forName(NAMESPACE + "LootTargets", false, loader);
            Class<?> boxes = Class.forName(NAMESPACE + "LootBoxes", false, loader);
            Class<?> target = Class.forName(NAMESPACE + "LootTargets$Target", false, loader);
            Class<?> lootRows = Class.forName(NAMESPACE + "LootRows", false, loader);
            Method add = targets.getDeclaredMethod("add", int.class, IsoGridSquare.class, IsoObject.class);
            Method grow = boxes.getDeclaredMethod("grow", int.class, float.class, float.class, float.class,
                    float.class, float.class, float.class);
            Field object = target.getDeclaredField("object");
            Field rows = lootRows.getDeclaredField("rows");
            Method nextSelectable = lootRows.getDeclaredMethod("nextSelectable", int.class, int.class);
            add.setAccessible(true);
            grow.setAccessible(true);
            object.setAccessible(true);
            rows.setAccessible(true);
            nextSelectable.setAccessible(true);
            binding = new Binding(add, grow, object, rows, nextSelectable);
        } catch (Exception | LinkageError error) {
            System.out.println(TAG + "Native interaction unavailable; using Lua menu: " + error);
        }
        return binding;
    }

    private static void fail(KahluaTable client, Throwable error) {
        binding = null;
        client.rawset("nativeActive", Boolean.FALSE);
        client.rawset("nativeBody", null);
        client.rawset("nativePath", null);
        System.out.println(TAG + "Native interaction disabled; using Lua menu: " + error);
    }

    private record Binding(Method add, Method grow, Field object, Field rows, Method nextSelectable) {}
}
