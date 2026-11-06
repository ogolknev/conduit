package dev.conduit.bridge;

import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import rikka.shizuku.Shizuku;

final class ClipboardRelay {
    private final BridgeService context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Shizuku.UserServiceArgs args;
    private final ExecutorService rpc = Executors.newSingleThreadExecutor();
    private final ExecutorService writes = Executors.newSingleThreadExecutor();
    private final AtomicReference<String> latestText = new AtomicReference<>();
    private final AtomicBoolean writing = new AtomicBoolean();
    private volatile DataInputStream incoming;
    private volatile DataOutputStream output;
    private volatile ParcelFileDescriptor commandPipe;
    private volatile int generation;
    private volatile boolean ready;
    private boolean starting;
    private volatile boolean disposed;
    private volatile String helperState = "not queried";
    private IBinder binder;
    static volatile String status = "Автобуфер выключен";
    private final AtomicLong sequence = new AtomicLong();
    private final Shizuku.OnBinderReceivedListener received = this::binderReceived;
    private final Shizuku.OnBinderDeadListener dead = this::binderDead;
    private ServiceConnection serviceConnection;
    private void binderReceived() { PhoneDiagnostics.record(context, "shizuku.binder.received"); startIfWanted(); }
    private void binderDead() { PhoneDiagnostics.record(context, "shizuku.binder.dead"); stopWithStatus("Shizuku остановлен. Запусти его снова."); }
    private ServiceConnection newConnection(final int version) { return new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder service) {
            main.post(() -> {
                if (version != generation || !wanted() || !starting) return;
                PhoneDiagnostics.record(context, "clipboard.service.bound");
                binder = service;
                new Thread(() -> run(service, version), "Conduit-clipboard-reader").start();
            });
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            if (version != generation) return;
            PhoneDiagnostics.record(context, "clipboard.service.disconnected");
            stopWithStatus("Сервис Shizuku отключился. Включи автобуфер снова.");
        }
    }; }
    ClipboardRelay(BridgeService context) {
        this.context = context;
        args = new Shizuku.UserServiceArgs(new ComponentName(context, ClipboardUserService.class)).daemon(false).version(4)
            .tag("clipboard-" + java.util.UUID.randomUUID()).processNameSuffix("clipboard");
        Shizuku.addBinderReceivedListenerSticky(received); Shizuku.addBinderDeadListener(dead);
    }
    boolean isReady() { return ready; }
    String helperDiagnostics() { return helperState; }
    void refreshHelperDiagnostics() {
        IBinder service = binder; final int version = generation;
        if (service == null || !ready || disposed) return;
        try { rpc.execute(() -> {
            if (version != generation) return;
            Parcel data = Parcel.obtain(), reply = Parcel.obtain();
            try {
                data.writeInterfaceToken(ClipboardUserService.DESCRIPTOR);
                if (!service.transact(3, data, reply, 0)) return;
                reply.readException(); Bundle state = reply.readBundle();
                if (state != null) helperState = "phase=" + state.getString("phase") + " uid=" + state.getInt("uid") +
                    " alive=" + state.getBoolean("processAlive") + " commandBytes=" + state.getLong("commandsBytes") +
                    " eventBytes=" + state.getLong("eventsBytes") + "\n" + state.getString("failure");
            } catch (Exception failure) { helperState = DiagnosticText.failure(failure); }
            finally { data.recycle(); reply.recycle(); }
        }); } catch (RejectedExecutionException ignored) { }
    }
    private boolean wanted() {
        return BridgeService.client != null && BridgeService.client.isBluetooth() && context.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean("autoClipboard", false);
    }
    void startIfWanted() {
        main.post(() -> {
            if (disposed) return;
            if (!wanted()) {
                if (context.getSharedPreferences("settings", 0).getBoolean("autoClipboard", false)) status = "Автобуфер ожидает подключения Mac";
                return;
            }
            if (ready || starting) return;
            try {
                if (!Shizuku.pingBinder() || Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                    status = "Запусти Shizuku и разреши Conduit"; PhoneDiagnostics.record(context, "clipboard.permission.missing"); return;
                }
                final int version = ++generation; starting = true; status = "Подключаю автобуфер…";
                final ServiceConnection target = newConnection(version); serviceConnection = target;
                PhoneDiagnostics.record(context, "clipboard.bind.request");
                rpc.execute(() -> {
                    try { Shizuku.bindUserService(args, target); }
                    catch (RuntimeException failure) { PhoneDiagnostics.record(context, "clipboard.bind.failed", failure); main.post(() -> { if (generation == version) stopWithStatus("Не удалось подключить Shizuku. Скопируй диагностику."); }); }
                });
                main.postDelayed(() -> {
                    if (generation == version && starting && !ready) {
                        PhoneDiagnostics.record(context, "clipboard.start.timeout"); stopWithStatus("Shizuku не подготовил автобуфер за 15 секунд. Скопируй диагностику.");
                    }
                }, 15000);
            } catch (RuntimeException failure) {
                PhoneDiagnostics.record(context, "clipboard.start.failed", failure); starting = false; status = "Не удалось подключить Shizuku";
            }
        });
    }
    private void run(IBinder service, int version) {
        DataInputStream input = null;
        DataOutputStream outgoing = null;
        ParcelFileDescriptor[][] pipes = new ParcelFileDescriptor[3][];
        try {
            final ParcelFileDescriptor[] asset = ParcelFileDescriptor.createPipe();
            pipes[0] = asset;
            final ParcelFileDescriptor[] commands = ParcelFileDescriptor.createPipe();
            pipes[1] = commands;
            final ParcelFileDescriptor[] events = ParcelFileDescriptor.createPipe();
            pipes[2] = events;
            new Thread(() -> {
                try (InputStream source = context.getAssets().open("scrcpy-server-v5.0.1"); OutputStream sink = new ParcelFileDescriptor.AutoCloseOutputStream(asset[1])) {
                    byte[] bytes = new byte[65536]; int n; while ((n = source.read(bytes)) != -1) sink.write(bytes, 0, n);
                    PhoneDiagnostics.record(context, "clipboard.asset.sent");
                } catch (IOException failure) { PhoneDiagnostics.record(context, "clipboard.asset.failed", failure); }
            }, "Conduit-server-asset").start();
            input = new DataInputStream(new ParcelFileDescriptor.AutoCloseInputStream(events[0]));
            outgoing = new DataOutputStream(new ParcelFileDescriptor.AutoCloseOutputStream(commands[1]));
            commandPipe = commands[1]; incoming = input;
            PhoneDiagnostics.record(context, "clipboard.helper.start");
            rpc.submit(() -> {
                Parcel data = Parcel.obtain(), reply = Parcel.obtain();
                try {
                    data.writeInterfaceToken(ClipboardUserService.DESCRIPTOR);
                    asset[0].writeToParcel(data, 0); commands[0].writeToParcel(data, 0); events[1].writeToParcel(data, 0);
                    if (!service.transact(1, data, reply, 0)) throw new IOException("No service");
                    reply.readException(); return true;
                } finally {
                    data.recycle(); reply.recycle(); asset[0].close(); commands[0].close(); events[1].close();
                }
            }).get(12, TimeUnit.SECONDS);
            if (generation != version) return;
            if (input.readUnsignedByte() != 0) throw new IOException("Invalid handshake");
            output = outgoing; ready = true;
            PhoneDiagnostics.record(context, "clipboard.pipe.ready");
            status = "Автобуфер через Shizuku подключён"; BridgeService.emit(BridgeService.status("status"));
            refreshHelperDiagnostics();
            // A queued request runs after scrcpy's controller has installed its clipboard listener.
            // It also recovers a copy made while the relay or Bluetooth connection was starting.
            requestSnapshot();
            while (generation == version) {
                int type = input.readUnsignedByte();
                if (type == 0) {
                    int size = input.readInt(); if (size < 0 || size > 262139) throw new IOException("Invalid clipboard size");
                    byte[] bytes = new byte[size]; input.readFully(bytes);
                    if (generation == version) { PhoneDiagnostics.record(context, "clipboard.auto.event"); BridgeService.sendClipboard(new String(bytes, StandardCharsets.UTF_8)); }
                } else if (type == 1) { input.readLong(); PhoneDiagnostics.record(context, "clipboard.helper.ack"); }
                else throw new IOException("Unexpected message");
            }
        } catch (Exception failure) {
            if (generation == version) { PhoneDiagnostics.record(context, "clipboard.reader.failed", failure); status = "Автобуфер прервался. Включи его снова или скопируй диагностику."; }
        } finally {
            for (ParcelFileDescriptor[] pipe : pipes) if (pipe != null) for (ParcelFileDescriptor end : pipe) try { end.close(); } catch (IOException ignored) {}
            if (input != null) try { input.close(); } catch (IOException ignored) {}
            if (outgoing != null) try { outgoing.close(); } catch (IOException ignored) {}
            if (generation == version) {
                ready = false; output = null; commandPipe = null;
                main.post(() -> { if (generation == version) { starting = false; BridgeService.emit(BridgeService.status("status")); } });
            }
        }
    }
    interface WriteOperation { void run() throws IOException; }
    void requestSnapshot() {
        final int version = generation; final IBinder service = binder;
        if (disposed || !ready || service == null) return;
        try { rpc.execute(() -> {
            if (generation != version) return;
            PhoneDiagnostics.record(context, "clipboard.snapshot.request");
            Parcel data = Parcel.obtain(), reply = Parcel.obtain();
            try {
                data.writeInterfaceToken(ClipboardUserService.DESCRIPTOR);
                if (!service.transact(4, data, reply, 0)) throw new IOException("Snapshot unavailable");
                reply.readException(); String text = reply.readString();
                if (generation == version && text != null) { PhoneDiagnostics.record(context, "clipboard.snapshot.event"); BridgeService.sendClipboard(text); }
                else if (generation == version) PhoneDiagnostics.record(context, "clipboard.snapshot.empty.or.locked");
            } catch (Exception failure) { PhoneDiagnostics.record(context, "clipboard.snapshot.failed", failure); }
            finally { data.recycle(); reply.recycle(); }
        }); } catch (RejectedExecutionException ignored) { }
    }
    private void guardedWrite(int version, WriteOperation operation) {
        AtomicBoolean pending = new AtomicBoolean(true);
        Runnable timeout = () -> {
            if (generation == version && pending.getAndSet(false)) {
                PhoneDiagnostics.record(context, "clipboard.command.timeout");
                stopWithStatus("Запись в Shizuku зависла. Включи автобуфер снова; Bluetooth остаётся активным.");
            }
        };
        main.postDelayed(timeout, 10000);
        try { operation.run(); }
        catch (IOException failure) { if (generation == version) { PhoneDiagnostics.record(context, "clipboard.command.failed", failure); stopWithStatus("Shizuku не принял буфер. Включи автобуфер снова."); } }
        finally { pending.set(false); main.removeCallbacks(timeout); }
    }
    void setText(String text) {
        if (disposed) return;
        PhoneDiagnostics.record(context, "clipboard.mac.received"); latestText.set(text);
        if (!writing.compareAndSet(false, true)) return;
        scheduleText();
    }
    private void scheduleText() {
        try { writes.execute(this::drainText); }
        catch (RejectedExecutionException ignored) { writing.set(false); latestText.set(null); }
    }
    private void drainText() {
        try {
            String text;
            while ((text = latestText.getAndSet(null)) != null) {
                if (disposed) return;
                final String value = text; final int version = generation; DataOutputStream stream = output;
                if (ready && stream != null) {
                    byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
                    guardedWrite(version, () -> {
                        stream.writeByte(9); stream.writeLong(sequence.incrementAndGet()); stream.writeByte(0); stream.writeInt(bytes.length); stream.write(bytes); stream.flush();
                        PhoneDiagnostics.record(context, "clipboard.command.written");
                    });
                } else main.post(() -> {
                    try { context.getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("Conduit", value)); PhoneDiagnostics.record(context, "clipboard.fallback.applied"); }
                    catch (RuntimeException failure) { PhoneDiagnostics.record(context, "clipboard.fallback.failed", failure); BridgeService.result(false, "Телефон не разрешил обновить буфер"); }
                });
            }
        } finally { writing.set(false); if (!disposed && latestText.get() != null && writing.compareAndSet(false, true)) scheduleText(); }
    }
    void stop() {
        stopWithStatus(context.getSharedPreferences("settings", 0).getBoolean("autoClipboard", false) ? "Автобуфер ожидает подключения Mac" : "Автобуфер выключен");
    }
    private void stopWithStatus(String reason) {
        main.post(() -> {
            if (disposed && rpc.isShutdown()) return;
            generation++; ready = false; starting = false; latestText.set(null);
            PhoneDiagnostics.record(context, "clipboard.stop");
            ParcelFileDescriptor pipe = commandPipe; commandPipe = null; if (pipe != null) try { pipe.close(); } catch (IOException ignored) {}
            DataOutputStream oldOutput = output; output = null;
            DataInputStream old = incoming; incoming = null; if (old != null) try { old.close(); } catch (IOException ignored) {}
            IBinder previous = binder; binder = null;
            ServiceConnection previousConnection = serviceConnection; serviceConnection = null;
            rpc.execute(() -> {
                if (oldOutput != null) try { oldOutput.close(); } catch (IOException ignored) {}
                if (previous != null) {
                    Parcel data = Parcel.obtain(), reply = Parcel.obtain();
                    try { data.writeInterfaceToken(ClipboardUserService.DESCRIPTOR); previous.transact(2, data, reply, 0); reply.readException(); }
                    catch (Exception failure) { PhoneDiagnostics.record(context, "clipboard.helper.stop.failed", failure); }
                    finally { data.recycle(); reply.recycle(); }
                }
                try { if (previousConnection != null && Shizuku.pingBinder()) Shizuku.unbindUserService(args, previousConnection, true); }
                catch (RuntimeException failure) { PhoneDiagnostics.record(context, "clipboard.unbind.failed", failure); }
            });
            status = reason; BridgeService.emit(BridgeService.status("status"));
            if (disposed) { writes.shutdownNow(); rpc.shutdown(); }
        });
    }
    void dispose() { disposed = true; Shizuku.removeBinderReceivedListener(received); Shizuku.removeBinderDeadListener(dead); stop(); }
}
