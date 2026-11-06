package dev.conduit.bridge;

import android.os.*;
import android.net.*;
import java.io.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import dalvik.system.PathClassLoader;

/** Runs only after a user grants Conduit permission in Shizuku. No arbitrary commands. */
public final class ClipboardUserService extends Binder {
    static final String DESCRIPTOR = "dev.conduit.ClipboardUserService";
    private java.lang.Process process;
    private File server;
    private final List<Closeable> streams = new ArrayList<>();
    private volatile int generation;
    private volatile String phase = "idle", failure = "none";
    private final AtomicLong commandsBytes = new AtomicLong(), eventsBytes = new AtomicLong();
    private volatile ClassLoader snapshotLoader;
    private volatile boolean snapshotInitialized;
    public ClipboardUserService() { attachInterface(null, DESCRIPTOR); }
    @Override protected synchronized boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
        if (code == INTERFACE_TRANSACTION) { reply.writeString(DESCRIPTOR); return true; }
        if (code == 16777115) { stop(); System.exit(0); return true; }
        data.enforceInterface(DESCRIPTOR);
        try {
            if (code == 3) {
                Bundle state = new Bundle(); state.putString("phase", phase); state.putString("failure", failure);
                state.putBoolean("processAlive", process != null && process.isAlive()); state.putInt("uid", android.os.Process.myUid());
                state.putLong("commandsBytes", commandsBytes.get()); state.putLong("eventsBytes", eventsBytes.get());
                reply.writeNoException(); reply.writeBundle(state); return true;
            }
            if (code == 4) {
                ClassLoader loader = snapshotLoader;
                if (loader == null) throw new IOException("Helper is not ready");
                FutureTask<String> read = new FutureTask<>(() -> {
                    if (!snapshotInitialized) { loader.loadClass("com.genymobile.scrcpy.Workarounds").getMethod("apply").invoke(null); snapshotInitialized = true; }
                    Object value = loader.loadClass("com.genymobile.scrcpy.device.Device").getMethod("getClipboardText").invoke(null);
                    return value instanceof String ? (String)value : null;
                });
                Looper looper = Looper.getMainLooper();
                if (looper == null) throw new IOException("No helper looper");
                new Handler(looper).post(read);
                String text = read.get(3, TimeUnit.SECONDS);
                if (text != null && text.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 262130) throw new IOException("Clipboard is too large");
                reply.writeNoException(); reply.writeString(text); return true;
            }
            if (code == 1) {
                stop();
                phase = "asset"; failure = "none"; commandsBytes.set(0); eventsBytes.set(0);
                ParcelFileDescriptor fd = ParcelFileDescriptor.CREATOR.createFromParcel(data);
                InputStream commands = new ParcelFileDescriptor.AutoCloseInputStream(ParcelFileDescriptor.CREATOR.createFromParcel(data));
                OutputStream events = new ParcelFileDescriptor.AutoCloseOutputStream(ParcelFileDescriptor.CREATOR.createFromParcel(data));
                streams.add(commands); streams.add(events);
                server = File.createTempFile("conduit-", ".jar", new File("/data/local/tmp"));
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(fd); OutputStream output = new FileOutputStream(server)) {
                    byte[] bytes = new byte[65536]; int n, size = 0;
                    while ((n = input.read(bytes)) != -1) { size += n; if (size > 1_048_576) throw new IOException("Invalid server"); output.write(bytes, 0, n); digest.update(bytes, 0, n); }
                }
                if (!BluetoothFiles.hex(digest.digest()).equals("764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536")) throw new IOException("Server checksum mismatch");
                if (!server.setReadOnly()) throw new IOException("Cannot protect verified server");
                snapshotLoader = new PathClassLoader(server.getAbsolutePath(), ClipboardUserService.class.getClassLoader());
                snapshotInitialized = false;
                String scid = String.format(Locale.US, "%08x", new SecureRandom().nextInt(Integer.MAX_VALUE));
                ProcessBuilder builder = new ProcessBuilder("/system/bin/app_process", "/", "com.genymobile.scrcpy.Server", "5.0.1",
                    "scid=" + scid, "video=false", "audio=false", "control=true", "tunnel_forward=true", "send_device_meta=false",
                    "send_dummy_byte=true", "clipboard_autosync=true", "power_on=false", "cleanup=false", "log_level=error");
                builder.environment().put("CLASSPATH", server.getAbsolutePath());
                builder.redirectOutput(new File("/dev/null")); builder.redirectError(new File("/dev/null"));
                phase = "spawn"; process = builder.start(); phase = "connect";
                LocalSocket local = null;
                for (int i = 0; i < 30; i++) {
                    local = new LocalSocket();
                    try { local.connect(new LocalSocketAddress("scrcpy_" + scid)); break; }
                    catch (IOException e) { local.close(); local = null; Thread.sleep(100); }
                }
                if (local == null) throw new IOException("Server unavailable");
                streams.add(local);
                // Only this shell process connects to the shell socket. The app uses anonymous Binder-passed pipes.
                phase = "forwarding";
                copyAsync(local.getInputStream(), events, false, generation);
                copyAsync(commands, local.getOutputStream(), true, generation);
                reply.writeNoException(); return true;
            }
            if (code == 2) { stop(); reply.writeNoException(); return true; }
        } catch (Exception e) {
            failure = DiagnosticText.failure(e);
            if (code == 1) { phase = "failed"; stop(); }
            reply.writeException(new IllegalStateException(code == 4 ? "Не удалось прочитать текущий буфер" : "Не удалось запустить привилегированный буфер")); return true;
        }
        return super.onTransact(code, data, reply, flags);
    }
    private void copyAsync(InputStream input, OutputStream output, boolean commands, int version) {
        Thread thread = new Thread(() -> {
            try {
                byte[] bytes = new byte[16384]; int n;
                while ((n = input.read(bytes)) != -1) {
                    output.write(bytes, 0, n); output.flush();
                    if (version == generation) (commands ? commandsBytes : eventsBytes).addAndGet(n);
                }
                if (version == generation) phase = commands ? "commands.eof" : "events.eof";
            }
            catch (IOException e) { if (version == generation) { phase = commands ? "commands.failed" : "events.failed"; failure = DiagnosticText.failure(e); } }
            finally { try { input.close(); } catch (IOException ignored) {} try { output.close(); } catch (IOException ignored) {} }
        }, "Conduit-clipboard-pipe"); thread.setDaemon(true); thread.start();
    }
    private void stop() {
        generation++;
        snapshotLoader = null; snapshotInitialized = false;
        for (Closeable stream : streams) try { stream.close(); } catch (IOException ignored) {}
        streams.clear();
        if (process != null) { process.destroy(); process = null; }
        if (server != null) { server.delete(); server = null; }
    }
}
