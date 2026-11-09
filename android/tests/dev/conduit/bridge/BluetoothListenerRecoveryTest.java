package dev.conduit.bridge;

public final class BluetoothListenerRecoveryTest {
    private static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        check(!BluetoothListenerRecovery.mayRestore(false, 36, true));
        check(!BluetoothListenerRecovery.mayRestore(true, 36, false));
        check(BluetoothListenerRecovery.mayRestore(true, 36, true));
        check(BluetoothListenerRecovery.mayRestore(true, 30, false));
        BluetoothListenerRecovery recovery = new BluetoothListenerRecovery();
        check(!recovery.begin(false, true, false)); // Explicit stop survives radio-on and reboot.
        check(!recovery.begin(true, false, false)); // Wait for the adapter instead of polling it.
        check(recovery.begin(true, true, false));
        check(!recovery.begin(true, true, false)); // Concurrent UI/system starts coalesce.
        recovery.completed(true, 0);
        check(!recovery.begin(true, true, true));
        check(recovery.retryDelay(100) == 2000);
        check(recovery.begin(true, true, false));
        recovery.completed(true, 2100);
        check(recovery.retryDelay(2200) == 5000); // Brief listener success must not erase backoff.
        check(recovery.retryDelay(2300) == 15000);
        check(recovery.retryDelay(2400) == 30000);
        check(recovery.retryDelay(2500) == 30000);
        recovery.completed(true, 3000);
        check(recovery.retryDelay(33000) == 2000); // A stable listener gets a fresh budget.
        recovery.retryDelay(33001);
        recovery.connected();
        check(recovery.retryDelay(33002) == 2000);
        System.out.println("Bluetooth listener recovery: restore consent, permissions, adapter state, coalescing and bounded backoff passed");
    }
}
