package dev.conduit.bridge;

import java.util.ArrayList;

/** Permission decisions use current grants, never the length/order of a vendor callback. */
final class BluetoothPermissions {
    static final String CONNECT = "android.permission.BLUETOOTH_CONNECT";
    static final String ADVERTISE = "android.permission.BLUETOOTH_ADVERTISE";
    static String[] missing(int sdk, boolean connectGranted, boolean advertiseGranted, boolean discoverable) {
        ArrayList<String> result = new ArrayList<>();
        if (sdk >= 31) {
            if (!connectGranted) result.add(CONNECT);
            if (discoverable && !advertiseGranted) result.add(ADVERTISE);
        }
        return result.toArray(new String[0]);
    }
}
