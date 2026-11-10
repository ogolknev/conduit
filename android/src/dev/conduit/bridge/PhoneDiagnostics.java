package dev.conduit.bridge;

import android.bluetooth.*;
import android.app.KeyguardManager;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.PowerManager;
import android.os.SystemClock;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import rikka.shizuku.Shizuku;

/** Fixed stage names and exception types only. Never pass payloads, keys or exception messages. */
final class PhoneDiagnostics {
    private static final int LIMIT = 262144;
    private static final AtomicLong sequence = new AtomicLong();
    private static final ConcurrentHashMap<String, AtomicLong> counters = new ConcurrentHashMap<>();
    static synchronized void record(Context context, String stage) { record(context, stage, null); }
    static synchronized void record(Context context, String stage, Throwable failure) {
        try {
            File file = new File(context.getFilesDir(), "connection.log");
            SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
            format.setTimeZone(TimeZone.getTimeZone("UTC"));
            counters.computeIfAbsent(stage, key -> new AtomicLong()).incrementAndGet();
            String line = format.format(new Date()) + " #" + sequence.incrementAndGet() + " uptime=" + SystemClock.elapsedRealtime() +
                " pid=" + android.os.Process.myPid() + " [" + stage + "]" + (failure == null ? "" : DiagnosticText.failure(failure)) + "\n";
            byte[] entry = line.getBytes(StandardCharsets.UTF_8);
            if (file.length() + entry.length > LIMIT) {
                byte[] previous = read(file);
                int start = Math.max(0, previous.length - LIMIT / 2);
                while (start < previous.length && previous[start] != '\n') start++;
                try (FileOutputStream out = new FileOutputStream(file)) {
                    if (start < previous.length) out.write(previous, start + 1, previous.length - start - 1);
                }
            }
            try (FileOutputStream out = new FileOutputStream(file, true)) { out.write(entry); }
        } catch (IOException ignored) {}
    }
    static String kind(String type) {
        switch (type) {
            case "ping": case "pong": case "clipboard": case "clipboardAck": case "preferences":
            case "diagnosticsRequest": case "diagnostics": case "reply": case "dismiss":
            case "fileBegin": case "fileChunk": case "fileEnd": case "fileReady": case "fileAck":
            case "fileDone": case "fileInfo": case "fileData": case "fileReceived": case "fileError":
            case "notificationSnapshot": case "notificationSnapshotEnd": case "notificationDismiss": case "notificationDismissed":
            case "notification": case "removed": case "status": case "ready": case "result": return type;
            default: return "other";
        }
    }
    static void frame(Context context, String direction, String type) { record(context, direction + "." + kind(type)); }
    static synchronized String report(Context context) {
        String version = "unknown";
        try { version = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName; }
        catch (PackageManager.NameNotFoundException ignored) {}
        StringBuilder result = new StringBuilder("Conduit Android ").append(version).append("\nAndroid SDK: ").append(Build.VERSION.SDK_INT);
        boolean connect = Build.VERSION.SDK_INT < 31 || context.checkSelfPermission(BluetoothPermissions.CONNECT) == PackageManager.PERMISSION_GRANTED;
        boolean advertise = Build.VERSION.SDK_INT < 31 || context.checkSelfPermission(BluetoothPermissions.ADVERTISE) == PackageManager.PERMISSION_GRANTED;
        result.append("\nBluetooth CONNECT: ").append(connect).append("\nBluetooth ADVERTISE: ").append(advertise);
        try {
            BluetoothManager manager = context.getSystemService(BluetoothManager.class);
            BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
            result.append("\nBluetooth power: ").append(connect && adapter != null ? adapter.isEnabled() : "unknown");
        } catch (RuntimeException ignored) { result.append("\nBluetooth power: unknown"); }
        result.append("\nService running: ").append(BridgeService.instance != null).append("\nStage: ").append(BluetoothLink.status).append("\n\n");
        PowerManager power = context.getSystemService(PowerManager.class);
        KeyguardManager keyguard = context.getSystemService(KeyguardManager.class);
        result.append("Device locked: ").append(keyguard != null && keyguard.isDeviceLocked()).append('\n');
        if (power != null) result.append("Screen on: ").append(power.isInteractive()).append("\nDevice idle: ").append(power.isDeviceIdleMode())
            .append("\nBattery saver: ").append(power.isPowerSaveMode()).append("\nBattery unrestricted: ").append(power.isIgnoringBatteryOptimizations(context.getPackageName()));
        result.append("\nMac connected: ").append(BridgeService.client != null)
            .append("\nBluetooth wanted: ").append(context.getSharedPreferences("settings", 0).getBoolean("bluetoothWanted", false))
            .append("\nAutoclipboard wanted: ").append(context.getSharedPreferences("settings", 0).getBoolean("autoClipboard", false))
            .append("\nClipboard stage: ").append(ClipboardRelay.status);
        try { result.append("\nShizuku alive: ").append(Shizuku.pingBinder()).append("\nShizuku permission: ").append(Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED); }
        catch (RuntimeException | LinkageError e) { result.append("\nShizuku unavailable: ").append(e.getClass().getSimpleName()); }
        BridgeService service = BridgeService.instance;
        if (service != null && service.clipboard != null) {
            service.clipboard.refreshHelperDiagnostics(); result.append("\nHelper: ").append(service.clipboard.helperDiagnostics());
        }
        result.append("\nConnection wake lock: ").append(service != null && service.hasConnectionWakeLock()).append("\n\nEvent counters (this process):\n");
        for (String key : new TreeSet<>(counters.keySet())) result.append(key).append('=').append(counters.get(key).get()).append('\n');
        result.append("\n--- Android log (latest entries) ---\n");
        try { result.append(DiagnosticText.tail(new String(read(new File(context.getFilesDir(), "connection.log")), StandardCharsets.UTF_8), 114688)); }
        catch (IOException ignored) {}
        return result.toString();
    }
    private static byte[] read(File file) throws IOException {
        try (InputStream in = new FileInputStream(file); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] bytes = new byte[2048]; int count;
            while ((count = in.read(bytes, 0, Math.min(bytes.length, LIMIT - out.size()))) > 0) out.write(bytes, 0, count);
            return out.toByteArray();
        }
    }
}
