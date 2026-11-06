package dev.conduit.bridge;

import android.app.*;
import android.content.*;
import android.net.*;
import android.os.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class BridgeService extends Service {
    static volatile BridgeService instance;
    static volatile Endpoint client;
    static volatile boolean remoteClipboardEnabled = true;
    BluetoothLink bluetooth;
    ClipboardRelay clipboard;
    static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final ScheduledExecutorService WATCHDOG = Executors.newSingleThreadScheduledExecutor();
    private volatile String token = "";
    private volatile boolean running;
    private LocalServerSocket server;
    private String foregroundFailure;
    private final ExecutorService bluetoothWorker = Executors.newSingleThreadExecutor();
    private PowerManager.WakeLock connectionWakeLock;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable renewPower = () -> updateConnectionPower();
    private final BroadcastReceiver powerEvents = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            PhoneDiagnostics.record(BridgeService.this, Intent.ACTION_SCREEN_OFF.equals(action) ? "power.screen.off" :
                Intent.ACTION_SCREEN_ON.equals(action) ? "power.screen.on" : Intent.ACTION_USER_PRESENT.equals(action) ? "power.user.present" : "power.mode.changed");
            emit(status("status"));
            if (Intent.ACTION_USER_PRESENT.equals(action) && clipboard != null) clipboard.requestSnapshot();
        }
    };

    @Override public void onCreate() {
        super.onCreate(); instance = this; bluetooth = new BluetoothLink(this);
        PhoneDiagnostics.record(this, "service.create");
        PowerManager power = getSystemService(PowerManager.class);
        if (power != null) { connectionWakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Conduit:Bluetooth"); connectionWakeLock.setReferenceCounted(false); }
        try {
            NotificationManager nm = getSystemService(NotificationManager.class);
            nm.createNotificationChannel(new NotificationChannel("connection", "Соединение с Mac", NotificationManager.IMPORTANCE_LOW));
            PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
            startForeground(1, new Notification.Builder(this, "connection").setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentTitle("Conduit").setContentText("Соединение с Mac").setContentIntent(open).setOngoing(true).build());
            PhoneDiagnostics.record(this, "service.foreground.ready");
        } catch (RuntimeException e) {
            PhoneDiagnostics.record(this, "service.foreground.failed", e);
            foregroundFailure = "Android не разрешил фоновую службу Conduit (" + e.getClass().getSimpleName() + "). Скопируй диагностику соединения.";
            BluetoothLink.status = foregroundFailure; return;
        }
        // Optional clipboard/ADB components must not prevent the Bluetooth listener from starting.
        try { clipboard = new ClipboardRelay(this); }
        catch (RuntimeException | LinkageError e) {
            ClipboardRelay.status = "Не удалось запустить модуль Shizuku";
            PhoneDiagnostics.record(this, "clipboard.init.failed", e);
        }
        running = true;
        IntentFilter events = new IntentFilter(Intent.ACTION_SCREEN_OFF); events.addAction(Intent.ACTION_SCREEN_ON);
        events.addAction(Intent.ACTION_USER_PRESENT);
        events.addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED); events.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(powerEvents, events, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(powerEvents, events);
        new Thread(() -> {
            LocalServerSocket local = null;
            try {
                local = new LocalServerSocket("conduit.bridge"); server = local;
                while (running) {
                    LocalSocket socket = local.accept();
                    int uid = socket.getPeerCredentials().getUid();
                    if (uid != 0 && uid != 2000) { socket.close(); continue; }
                    new Thread(() -> handle(socket), "Conduit-client").start();
                }
            } catch (IOException | RuntimeException e) {
                if (running) PhoneDiagnostics.record(this, "adb.listener.failed", e);
            } finally { if (local != null) try { local.close(); } catch (IOException ignored) {} }
        }, "Conduit-accept").start();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "STOP".equals(intent.getAction())) {
            getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("bluetoothWanted", false).apply(); stopSelf(); return START_NOT_STICKY;
        }
        if (foregroundFailure != null) {
            startupResult(intent == null ? null : intent.getParcelableExtra("startupReceiver"), false, foregroundFailure);
            stopSelf(); return START_NOT_STICKY;
        }
        if (intent != null) {
            String incoming = intent.getStringExtra("token");
            if (incoming != null && incoming.matches("[a-fA-F0-9]{64}")) {
                token = incoming;
                Endpoint old = client; if (old != null) old.close();
            }
        }
        boolean bluetoothStart = intent != null && "BLUETOOTH_START".equals(intent.getAction());
        if (bluetoothStart) getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("bluetoothWanted", true).apply();
        boolean wanted = getSharedPreferences("settings", MODE_PRIVATE).getBoolean("bluetoothWanted", false);
        if (bluetoothStart || (intent == null && wanted)) {
            final ResultReceiver receiver = intent == null ? null : intent.getParcelableExtra("startupReceiver");
            bluetoothWorker.execute(() -> {
                BluetoothLink.StartResult result = bluetooth.start();
                startupResult(receiver, result.ready, result.message);
            });
        }
        if (intent != null && "CLIPBOARD_START".equals(intent.getAction()) && clipboard != null) clipboard.startIfWanted();
        return wanted ? START_STICKY : START_NOT_STICKY;
    }
    boolean hasConnectionWakeLock() { return connectionWakeLock != null && connectionWakeLock.isHeld(); }
    private void updateConnectionPower() {
        main.removeCallbacks(renewPower);
        try {
            if (running && client != null && client.isBluetooth()) {
                if (connectionWakeLock != null) connectionWakeLock.acquire(120000);
                main.postDelayed(renewPower, 60000);
            } else if (hasConnectionWakeLock()) connectionWakeLock.release();
        } catch (RuntimeException e) { PhoneDiagnostics.record(this, "power.wakelock.failed", e); }
    }
    private static void startupResult(ResultReceiver receiver, boolean ready, String message) {
        if (receiver == null) return;
        Bundle data = new Bundle(); data.putString("message", message); receiver.send(ready ? 1 : 0, data);
    }

    private void handle(LocalSocket socket) {
        Client session = null;
        try {
            socket.setSoTimeout(5000);
            InputStream input = socket.getInputStream();
            JSONObject hello = new JSONObject(readLine(input, 4096));
            String supplied = hello.optString("token");
            if (!"hello".equals(hello.optString("type")) || hello.optInt("protocol") != 1 || token.length() != 64 ||
                !MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8), supplied.getBytes(StandardCharsets.UTF_8))) return;
            socket.setSoTimeout(0);
            session = new Client(socket);
            // The ready frame must precede any event in a new stream.
            session.send(status("ready", 1));
            activate(session);
            SharedFiles.sendPending(this);
            while (running && client == session) {
                JSONObject message = new JSONObject(readLine(input, 65536));
                handleCommand(this, session, message);
            }
        } catch (Exception ignored) {
            // Never log notification content, tokens, or reply text.
        } finally {
            if (session != null) deactivate(session);
            try { socket.close(); } catch (IOException ignored) {}
        }
    }

    static JSONObject object(Object... pairs) {
        JSONObject object = new JSONObject();
        try { for (int i = 0; i < pairs.length; i += 2) object.put((String)pairs[i], pairs[i + 1]); }
        catch (JSONException ignored) {}
        return object;
    }
    static synchronized void activate(Endpoint next) {
        Endpoint old = client; client = next; remoteClipboardEnabled = true;
        if (old != null && old != next) old.close();
        BridgeService service = instance;
        if (service != null) {
            service.updateConnectionPower();
            if (service.clipboard != null) { if (next.isBluetooth()) service.clipboard.startIfWanted(); else service.clipboard.stop(); }
        }
        if (service != null) PhoneDiagnostics.record(service, "peer.active");
    }
    static synchronized void deactivate(Endpoint previous) {
        if (client != previous) return;
        client = null;
        BridgeService service = instance;
        if (service != null) { service.updateConnectionPower(); if (service.clipboard != null) service.clipboard.stop(); PhoneDiagnostics.record(service, "peer.inactive"); }
    }
    static JSONObject status(String type) { return status(type, client != null && client.isBluetooth() ? 2 : 1); }
    private static boolean deviceLocked(Context context) {
        KeyguardManager keyguard = context.getSystemService(KeyguardManager.class);
        return keyguard != null && keyguard.isDeviceLocked();
    }
    static JSONObject status(String type, int protocol) {
        BridgeService service = instance;
        return object("type", type, "protocol", protocol, "notificationAccess", service != null && PhoneNotifications.hasAccess(service),
            "clipboardAuto", service != null && service.clipboard != null && service.clipboard.isReady(),
            "deviceLocked", service != null && deviceLocked(service));
    }
    static void emit(JSONObject message) { emitTo(client, message); }
    static void emitTo(Endpoint target, JSONObject message) {
        if (target == null) return;
        try {
            target.writer.execute(() -> {
                try { target.send(message); } catch (IOException e) { deactivate(target); target.close(); }
            });
        } catch (RejectedExecutionException e) { deactivate(target); target.close(); }
    }
    static void handleCommand(Context context, Endpoint endpoint, JSONObject message) throws IOException {
        if (client != endpoint) throw new IOException("Session replaced");
        String type = message.optString("type");
        PhoneDiagnostics.frame(context, "rx", type);
        if ("ping".equals(type)) emitTo(endpoint, object("type", "pong", "deviceLocked", deviceLocked(context)));
        else if ("diagnosticsRequest".equals(type)) {
            long now = SystemClock.elapsedRealtime();
            if (now - endpoint.lastDiagnosticsAt >= 5000) {
                endpoint.lastDiagnosticsAt = now;
                IO.execute(() -> { if (client == endpoint) emitTo(endpoint, object("type", "diagnostics", "report", PhoneDiagnostics.report(context))); });
            }
        }
        else if ("clipboardAck".equals(type)) PhoneDiagnostics.record(context, "clipboard.mac.applied");
        else if ("reply".equals(type)) PhoneNotifications.reply(message.optString("key"), message.optString("text"));
        else if ("dismiss".equals(type)) PhoneNotifications.dismiss(message.optString("key"));
        else if ("fileReceived".equals(type)) { if (endpoint instanceof BluetoothLink.Peer) ((BluetoothLink.Peer)endpoint).files.received(message.optString("name")); SharedFiles.acknowledge(context, message.optString("name")); }
        else if ("preferences".equals(type)) remoteClipboardEnabled = message.optBoolean("clipboard", true);
        else if ("clipboard".equals(type) && endpoint.isBluetooth() && remoteClipboardEnabled) {
            String text = message.optString("text");
            BridgeService service = instance;
            if (text.getBytes(StandardCharsets.UTF_8).length <= 262130 && service != null) {
                if (service.clipboard != null) service.clipboard.setText(text);
                else new Handler(Looper.getMainLooper()).post(() -> {
                    try { service.getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("Conduit", text)); }
                    catch (RuntimeException e) { result(false, "Телефон не разрешил обновить буфер"); }
                });
            }
        } else if (endpoint instanceof BluetoothLink.Peer && type.startsWith("file")) ((BluetoothLink.Peer)endpoint).files.handle(message);
    }
    static void sendClipboard(String text) {
        if (remoteClipboardEnabled && text != null && text.getBytes(StandardCharsets.UTF_8).length <= 262130) {
            if (instance != null) PhoneDiagnostics.record(instance, client == null ? "clipboard.no.peer" : "clipboard.enqueue");
            emit(object("type", "clipboard", "text", text));
        }
    }
    static void result(boolean ok, String message) { emit(object("type", "result", "ok", ok, "message", message)); }

    static String readLine(InputStream input, int limit) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        int next;
        while ((next = input.read()) != -1) {
            if (next == '\n') return buffer.toString("UTF-8");
            if (buffer.size() >= limit) throw new IOException("Frame too long");
            buffer.write(next);
        }
        throw new EOFException();
    }

    static abstract class Endpoint {
        private final OutputStream output;
        final ThreadPoolExecutor writer = new ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS,
            new ArrayBlockingQueue<Runnable>(32), new ThreadPoolExecutor.AbortPolicy());
        long lastDiagnosticsAt = -5000;
        Endpoint(OutputStream output) { this.output = output; }
        synchronized void send(JSONObject message) throws IOException {
            byte[] bytes = (message.toString() + "\n").getBytes(StandardCharsets.UTF_8);
            if (bytes.length > 1_048_576) throw new IOException("Frame too long");
            AtomicBoolean pending = new AtomicBoolean(true);
            ScheduledFuture<?> timeout = WATCHDOG.schedule(() -> {
                if (pending.getAndSet(false)) {
                    if (instance != null) PhoneDiagnostics.record(instance, "tx.timeout");
                    deactivate(this); close();
                }
            }, 15, TimeUnit.SECONDS);
            try {
                if (instance != null) PhoneDiagnostics.frame(instance, "tx.begin", message.optString("type"));
                output.write(bytes); output.flush();
                if (instance != null) PhoneDiagnostics.frame(instance, "tx.done", message.optString("type"));
            } finally { pending.set(false); timeout.cancel(false); }
        }
        final void closeWriter() { writer.shutdownNow(); }
        abstract boolean isBluetooth();
        abstract void close();
    }
    static final class Client extends Endpoint {
        private final LocalSocket socket;
        Client(LocalSocket socket) throws IOException { super(socket.getOutputStream()); this.socket = socket; }
        @Override boolean isBluetooth() { return false; }
        @Override void close() { closeWriter(); try { socket.close(); } catch (IOException ignored) {} }
    }
    @Override public void onDestroy() {
        running = false; bluetoothWorker.shutdownNow(); bluetooth.stop(); if (clipboard != null) clipboard.dispose(); instance = null;
        updateConnectionPower(); main.removeCallbacks(renewPower);
        try { unregisterReceiver(powerEvents); } catch (IllegalArgumentException ignored) {}
        PhoneDiagnostics.record(this, "service.destroy");
        Endpoint old = client; client = null; if (old != null) old.close();
        if (server != null) try { server.close(); } catch (IOException ignored) {}
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override protected void dump(FileDescriptor descriptor, PrintWriter writer, String[] arguments) {
        writer.print(PhoneDiagnostics.report(this));
    }
}
