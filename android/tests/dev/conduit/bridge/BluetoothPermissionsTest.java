package dev.conduit.bridge;

import java.util.Arrays;

public final class BluetoothPermissionsTest {
    private static void expect(int sdk, boolean connect, boolean advertise, boolean discoverable, String... wanted) {
        String[] actual = BluetoothPermissions.missing(sdk, connect, advertise, discoverable);
        if (!Arrays.equals(actual, wanted)) throw new AssertionError("sdk=" + sdk + " discoverable=" + discoverable + " actual=" + Arrays.toString(actual));
    }
    public static void main(String[] args) {
        // Listening for an already paired Mac never requires discoverability permission.
        expect(35, true, false, false);
        expect(31, true, false, false);
        expect(35, false, false, false, BluetoothPermissions.CONNECT);
        // New pairing has its own extra permission, requested only while missing.
        expect(35, true, false, true, BluetoothPermissions.ADVERTISE);
        expect(35, false, true, true, BluetoothPermissions.CONNECT);
        expect(35, false, false, true, BluetoothPermissions.CONNECT, BluetoothPermissions.ADVERTISE);
        expect(35, true, true, true);
        // A callback with partial/interrupted results is followed by checking current grants.
        expect(35, true, false, false);
        expect(35, false, true, false, BluetoothPermissions.CONNECT);
        // Android 8–11 use the manifest permissions, without the new runtime prompt.
        expect(26, false, false, true);
        expect(30, false, false, false);
        System.out.println("Bluetooth permission regressions passed (11 scenarios)");
    }
}
