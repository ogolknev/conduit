package dev.conduit.bridge;

import static dev.conduit.bridge.I18n.t;

import android.app.*;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.*;
import android.os.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
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
    private final BluetoothListenerRecovery listenerRecovery = new BluetoothListenerRecovery();
    private final ArrayList<ResultReceiver> startupReceivers = new ArrayList<>();
    private boolean bluetoothRetryScheduled;
    private final Runnable retryBluetooth = () -> { bluetoothRetryScheduled = false; ensureBluetoothListener(null); };
    private final Runnable renewPower = () -> updateConnectionPower();
    private final BroadcastReceiver bluetoothEvents = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            int state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR);
            PhoneDiagnostics.record(BridgeService.this, "bluetooth.state." + state);
            if (state == BluetoothAdapter.STATE_TURNING_OFF || state == BluetoothAdapter.STATE_OFF) {
                cancelBluetoothRetry(); bluetooth.suspend(); updateConnectionPower();
            } else if (state == BluetoothAdapter.STATE_ON) {
                cancelBluetoothRetry(); ensureBluetoothListener(null);
            }
        }
    };
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
            nm.createNotificationChannel(new NotificationChannel("connection", t("Соединение с Mac"), NotificationManager.IMPORTANCE_LOW));
            startForeground(1, connectionNotification());
            PhoneDiagnostics.record(this, "service.foreground.ready");
            PhoneNotifications.ensureConnected(this);
        } catch (RuntimeException e) {
            PhoneDiagnostics.record(this, "service.foreground.failed", e);
            foregroundFailure = t("Android не разрешил фоновую службу Conduit (") + e.getClass().getSimpleName() + t("). Скопируй диагностику соединения.");
            BluetoothLink.status = foregroundFailure; return;
        }
        // Optional clipboard/ADB components must not prevent the Bluetooth listener from starting.
        try { clipboard = new ClipboardRelay(this); }
        catch (RuntimeException | LinkageError e) {
            ClipboardRelay.status = t("Не удалось запустить модуль Shizuku");
            PhoneDiagnostics.record(this, "clipboard.init.failed", e);
        }
        running = true;
        IntentFilter events = new IntentFilter(Intent.ACTION_SCREEN_OFF); events.addAction(Intent.ACTION_SCREEN_ON);
        events.addAction(Intent.ACTION_USER_PRESENT);
        events.addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED); events.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(powerEvents, events, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(powerEvents, events);
        // Bluetooth broadcasts originate in a privileged Bluetooth process, not always system UID.
        IntentFilter bluetoothState = new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(bluetoothEvents, bluetoothState, Context.RECEIVER_EXPORTED);
        else registerReceiver(bluetoothEvents, bluetoothState);
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

    @Override public void onConfigurationChanged(android.content.res.Configuration configuration) {
        super.onConfigurationChanged(configuration); I18n.refresh(getApplicationContext());
        NotificationManager manager=getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel("connection",t("Соединение с Mac"),NotificationManager.IMPORTANCE_LOW));
        if (running) manager.notify(1,connectionNotification());
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
        boolean wanted = bluetoothWanted(this);
        if (wanted) ensureBluetoothListener(intent == null ? null : intent.getParcelableExtra("startupReceiver"));
        else if (intent != null && "BLUETOOTH_RESTORE".equals(intent.getAction())) { stopSelf(startId); return START_NOT_STICKY; }
        if (intent != null && "CLIPBOARD_START".equals(intent.getAction()) && clipboard != null) clipboard.startIfWanted();
        return wanted ? START_STICKY : START_NOT_STICKY;
    }
    static boolean bluetoothWanted(Context context) {
        android.content.SharedPreferences prefs = context.getSharedPreferences("settings", MODE_PRIVATE);
        return prefs.getBoolean("bluetoothWanted", prefs.getBoolean("autoClipboard", false)
            || !context.getSharedPreferences("bluetooth-trust", MODE_PRIVATE).getAll().isEmpty());
    }
    static void restoreIfWanted(Context context) {
        boolean permission = Build.VERSION.SDK_INT < 31 || context.checkSelfPermission(BluetoothPermissions.CONNECT) == PackageManager.PERMISSION_GRANTED;
        if (!BluetoothListenerRecovery.mayRestore(bluetoothWanted(context), Build.VERSION.SDK_INT, permission)) return;
        BridgeService current = instance;
        if (current != null && current.running) { current.ensureBluetoothListener(null); return; }
        try {
            context.startForegroundService(new Intent(context, BridgeService.class).setAction("BLUETOOTH_RESTORE"));
            PhoneDiagnostics.record(context, "service.restore.request");
        } catch (RuntimeException failure) {
            BluetoothLink.status = t("Android ограничил фоновый запуск. Открой Conduit для восстановления соединения.");
            PhoneDiagnostics.record(context, "service.restore.failed", failure);
        }
    }
    private boolean bluetoothAvailable() {
        try {
            BluetoothManager manager = getSystemService(BluetoothManager.class);
            return manager != null && manager.getAdapter() != null && manager.getAdapter().isEnabled();
        } catch (SecurityException failure) { return false; }
    }
    private void deliverStartupResults(boolean ready, String message) {
        for (ResultReceiver receiver : startupReceivers) startupResult(receiver, ready, message);
        startupReceivers.clear();
    }
    private void ensureBluetoothListener(ResultReceiver receiver) {
        if (receiver != null) startupReceivers.add(receiver);
        if (!running || !bluetoothWanted(this)) { deliverStartupResults(false, t("Соединение остановлено")); return; }
        if (bluetooth.isListening()) { deliverStartupResults(true, BluetoothLink.status); return; }
        if (listenerRecovery.isStarting()) return;
        if (!bluetoothAvailable()) {
            BluetoothLink.status = t("Bluetooth выключен. Соединение восстановится после включения.");
            deliverStartupResults(false, BluetoothLink.status); updateConnectionPower(); return;
        }
        if (!listenerRecovery.begin(true, true, false)) return;
        cancelBluetoothRetry();
        bluetoothWorker.execute(() -> {
            BluetoothLink.StartResult result = bluetooth.start();
            main.post(() -> {
                if (!running) return;
                boolean ready = result.ready && bluetooth.isListening();
                listenerRecovery.completed(ready, SystemClock.elapsedRealtime());
                deliverStartupResults(ready, ready ? result.message : BluetoothLink.status);
                if (!ready) scheduleBluetoothRetry();
                updateConnectionPower(); emit(status("status"));
            });
        });
    }
    void bluetoothListenerStopped() {
        main.post(() -> { if (running && !listenerRecovery.isStarting()) scheduleBluetoothRetry(); });
    }
    private void scheduleBluetoothRetry() {
        if (!running || !bluetoothWanted(this) || !bluetoothAvailable() || bluetooth.isListening() || bluetoothRetryScheduled) return;
        long delay = listenerRecovery.retryDelay(SystemClock.elapsedRealtime());
        bluetoothRetryScheduled = true;
        PhoneDiagnostics.record(this, "listener.retry." + delay + "ms");
        main.postDelayed(retryBluetooth, delay);
    }
    private void cancelBluetoothRetry() { main.removeCallbacks(retryBluetooth); bluetoothRetryScheduled = false; }
    boolean isBluetoothListening() { return bluetooth!=null && bluetooth.isListening(); }
    boolean hasConnectionWakeLock() { return connectionWakeLock != null && connectionWakeLock.isHeld(); }
    private Notification connectionNotification() {
        Endpoint peer=client;
        String text=peer==null?(bluetoothAvailable()?t("Ожидание Mac"):t("Bluetooth выключен. Соединение восстановится после включения.")):peer.isBluetooth()?t("Mac подключён · Bluetooth"):t("Mac подключён · Отладка");
        PendingIntent open=PendingIntent.getActivity(this,0,new Intent(this,MainActivity.class),PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this,"connection").setSmallIcon(R.drawable.ic_notification).setContentTitle("Conduit").setContentText(text)
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false).build();
    }
    private void updateConnectionPower() {
        main.removeCallbacks(renewPower);
        try { getSystemService(NotificationManager.class).notify(1,connectionNotification()); } catch(RuntimeException ignored) {}
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
            service.main.post(() -> service.listenerRecovery.connected());
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
        return object("type", type, "protocol", protocol, "notificationInbox", 1, "notificationSource", service == null ? "" : PhoneNotifications.source(service), "notificationListenerConnected",PhoneNotifications.isConnected(), "notificationAccess", service != null && PhoneNotifications.hasAccess(service),
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
        else if ("reply".equals(type)) PhoneNotifications.reply(message.optString("key"), message.optString("text"), message.optString("instance"), endpoint, message.optString("request"));
        else if ("notificationSnapshot".equals(type)) PhoneNotifications.snapshot(endpoint, message.optString("request"));
        else if ("notificationDismiss".equals(type)) PhoneNotifications.dismissTracked(endpoint, message.optString("key"), message.optString("instance"));
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
                    catch (RuntimeException e) { result(false, t("Телефон не разрешил обновить буфер")); }
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
        running = false; cancelBluetoothRetry(); bluetoothWorker.shutdownNow(); bluetooth.stop(); if (clipboard != null) clipboard.dispose(); instance = null;
        updateConnectionPower(); main.removeCallbacks(renewPower);
        try { unregisterReceiver(powerEvents); } catch (IllegalArgumentException ignored) {}
        try { unregisterReceiver(bluetoothEvents); } catch (IllegalArgumentException ignored) {}
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
