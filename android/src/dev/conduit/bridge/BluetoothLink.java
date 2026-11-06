package dev.conduit.bridge;

import static dev.conduit.bridge.I18n.t;

import android.bluetooth.*;
import android.content.*;
import android.os.*;
import org.json.*;
import java.io.*;
import java.security.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

final class BluetoothLink {
    static final UUID SERVICE = UUID.fromString("831e2350-1d98-4ed9-8bd1-65cda12a5ad0");
    static final PairingCode PAIRING = new PairingCode(SystemClock::elapsedRealtime, new SecureRandom());
    static volatile String status = t("Bluetooth выключен в Conduit");
    private final BridgeService context;
    private volatile boolean running;
    private volatile int generation;
    private boolean closed;
    private BluetoothServerSocket server;
    private final Semaphore handshakes = new Semaphore(2);
    BluetoothLink(BridgeService context) { this.context = context; }
    boolean isListening() { return running; }
    static final class StartResult {
        final boolean ready; final String message;
        StartResult(boolean ready, String message) { this.ready = ready; this.message = message; }
    }
    private static String readyMessage() {
        return BridgeService.client != null && BridgeService.client.isBluetooth() ? t("Mac подключён по Bluetooth") : t("Bluetooth готов. Выбери телефон в Conduit на Mac.");
    }
    StartResult start() {
        final int version;
        synchronized (this) {
            if (closed) return new StartResult(false, t("Соединение остановлено. Нажми «Включить» снова."));
            if (running && server != null) { status = readyMessage(); return new StartResult(true, status); }
            version = ++generation;
        }
        BluetoothServerSocket listener = null;
        try {
            BluetoothManager manager = context.getSystemService(BluetoothManager.class);
            BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
            if (adapter == null || !adapter.isEnabled()) return failedStart(version, t("Включи Bluetooth на телефоне"), "listener.adapter.off", null);
            // Secure RFCOMM mandates link authentication and encryption.
            PhoneDiagnostics.record(context, "listener.open");
            listener = adapter.listenUsingRfcommWithServiceRecord("Conduit", SERVICE);
            final BluetoothServerSocket socket = listener;
            synchronized (this) {
                if (closed || generation != version) { listener.close(); return new StartResult(false, t("Соединение остановлено")); }
                server = listener; running = true; status = readyMessage();
                new Thread(() -> listen(socket, version), "Conduit-bt-listener").start();
            }
            PhoneDiagnostics.record(context, "listener.ready");
            return new StartResult(true, status);
        } catch (SecurityException e) {
            close(listener); return failedStart(version, t("Разреши Conduit доступ к устройствам поблизости в настройках приложения."), "listener.permission.failed", e);
        } catch (IOException | RuntimeException e) {
            close(listener); return failedStart(version, t("Не удалось запустить Bluetooth-сервис (") + e.getClass().getSimpleName() + t("). Скопируй диагностику соединения."), "listener.open.failed", e);
        }
    }
    private synchronized StartResult failedStart(int version, String message, String stage, Throwable failure) {
        if (generation == version && !closed) { running = false; server = null; status = message; PhoneDiagnostics.record(context, stage, failure); }
        return new StartResult(false, message);
    }
    private boolean current(int version) { return running && generation == version; }
    private static void close(BluetoothServerSocket socket) { if (socket != null) try { socket.close(); } catch (IOException ignored) {} }
    private void listen(BluetoothServerSocket listener, int version) {
        try {
            while (current(version)) {
                BluetoothSocket socket = listener.accept();
                if (!current(version) || !handshakes.tryAcquire()) { socket.close(); continue; }
                new Thread(() -> accept(socket, version), "Conduit-bt-peer").start();
            }
        } catch (IOException | RuntimeException e) {
            synchronized (this) {
                if (current(version)) {
                    status = t("Bluetooth отключился (") + e.getClass().getSimpleName() + t("). Нажми «Включить» снова.");
                    PhoneDiagnostics.record(context, "listener.accept.failed", e);
                }
            }
        } finally {
            close(listener);
            synchronized (this) { if (generation == version) { running = false; server = null; } }
        }
    }
    private void accept(BluetoothSocket socket, int version) {
        Peer peer = null;
        Handler timer = new Handler(Looper.getMainLooper());
        final AtomicBoolean waiting = new AtomicBoolean(true);
        Runnable timeout = () -> { if (waiting.get()) try { socket.close(); } catch (IOException ignored) {} };
        timer.postDelayed(timeout, 10000);
        try {
            PhoneDiagnostics.record(context, "peer.accept");
            if (socket.getRemoteDevice().getBondState() != BluetoothDevice.BOND_BONDED) return;
            InputStream input = socket.getInputStream();
            JSONObject hello = new JSONObject(BridgeService.readLine(input, 4096));
            String id = hello.optString("client");
            if (!"hello".equals(hello.optString("type")) || hello.optInt("protocol") != 2 || !validUUID(id)) return;
            SharedPreferences prefs = context.getSharedPreferences("bluetooth-trust", Context.MODE_PRIVATE);
            String stored = prefs.getString(id, "");
            String supplied = hello.optString("token");
            boolean remembered = stored.length() == 64 && MessageDigest.isEqual(stored.getBytes(StandardCharsets.US_ASCII), supplied.getBytes(StandardCharsets.US_ASCII));
            String issued = null;
            if (!remembered) {
                if (!PAIRING.verify(hello.optString("code"))) {
                    socket.getOutputStream().write("{\"type\":\"authError\"}\n".getBytes(StandardCharsets.UTF_8)); return;
                }
                byte[] key = new byte[32]; new SecureRandom().nextBytes(key);
                StringBuilder token = new StringBuilder(); for (byte b : key) token.append(String.format(java.util.Locale.US,"%02x", b & 255));
                issued = token.toString();
                if (!prefs.edit().putString(id, issued).commit()) return;
            }
            peer = new Peer(socket, context);
            JSONObject ready = BridgeService.status("ready", 2);
            if (issued != null) ready.put("token", issued);
            peer.send(ready);
            if (waiting.getAndSet(false)) handshakes.release(); timer.removeCallbacks(timeout);
            synchronized (this) {
                if (!current(version)) return;
                BridgeService.activate(peer); status = t("Mac подключён по Bluetooth");
            }
            PhoneDiagnostics.record(context, "peer.ready");
            SharedFiles.sendPending(context);
            while (current(version) && BridgeService.client == peer) {
                JSONObject message = new JSONObject(BridgeService.readLine(input, 1_048_576));
                BridgeService.handleCommand(context, peer, message);
            }
        } catch (Exception failure) { PhoneDiagnostics.record(context, "peer.failed", failure); }
        finally {
            PhoneDiagnostics.record(context, "peer.closed");
            if (waiting.getAndSet(false)) handshakes.release();
            timer.removeCallbacks(timeout);
            if (peer != null) { BridgeService.deactivate(peer); peer.close(); }
            try { socket.close(); } catch (IOException ignored) {}
            synchronized (this) { if (current(version) && BridgeService.client == null) status = t("Ожидаю Mac по Bluetooth"); }
        }
    }
    static boolean validUUID(String value) {
        try { return UUID.fromString(value).toString().equalsIgnoreCase(value); } catch (Exception e) { return false; }
    }
    void stop() {
        BluetoothServerSocket previous;
        synchronized (this) { closed = true; generation++; running = false; previous = server; server = null; status = t("Bluetooth выключен в Conduit"); }
        close(previous);
        BridgeService.Endpoint current = BridgeService.client;
        if (current != null && current.isBluetooth()) { BridgeService.deactivate(current); current.close(); }
        PhoneDiagnostics.record(context, "listener.stopped");
    }
    static final class Peer extends BridgeService.Endpoint {
        private final BluetoothSocket socket;
        final BluetoothFiles files;
        Peer(BluetoothSocket socket, Context context) throws IOException { super(socket.getOutputStream()); this.socket = socket; files = new BluetoothFiles(context, this); }
        @Override boolean isBluetooth() { return true; }
        @Override void close() { closeWriter(); try { socket.close(); } catch (IOException ignored) {} files.close(); }
    }
}
