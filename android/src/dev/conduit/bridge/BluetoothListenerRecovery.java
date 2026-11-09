package dev.conduit.bridge;

/** Listener recovery decisions are independent of UI and Android callback ordering. */
final class BluetoothListenerRecovery {
    private boolean starting;
    private int failures;
    private long readyAt = -1;

    static boolean mayRestore(boolean wanted, int sdk, boolean connectGranted) {
        return wanted && (sdk < 31 || connectGranted);
    }
    boolean begin(boolean wanted, boolean available, boolean listening) {
        if (!wanted || !available || listening || starting) return false;
        starting = true;
        return true;
    }
    void completed(boolean listening, long now) {
        starting = false;
        if (listening) readyAt = now;
    }
    boolean isStarting() { return starting; }
    void connected() { failures = 0; }
    long retryDelay(long now) {
        if (readyAt >= 0 && now - readyAt >= 30000) failures = 0;
        readyAt = -1;
        long[] delays = {2000, 5000, 15000, 30000};
        long delay = delays[Math.min(failures, delays.length - 1)];
        failures = Math.min(failures + 1, delays.length);
        return delay;
    }
}
