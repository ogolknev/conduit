package dev.conduit.bridge;

import static dev.conduit.bridge.I18n.t;

import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import android.widget.Toast;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.UUID;

final class SharedFiles {
    private static final long MAX = 1_073_741_824L;
    static void share(Context context, Uri uri) {
        Context app = context.getApplicationContext();
        BridgeService.IO.execute(() -> {
            File payload = null, metadata = null;
            String id=UUID.randomUUID().toString()+".bin";
            try {
                File outbox = new File(app.getExternalFilesDir(null), "outbox");
                File index = new File(app.getFilesDir(), "shares");
                if ((!outbox.isDirectory() && !outbox.mkdirs()) || (!index.isDirectory() && !index.mkdirs())) throw new IOException(t("Хранилище недоступно"));
                long used = 0; File[] existing = outbox.listFiles();
                if (existing != null) {
                    if (existing.length >= 32) throw new IOException(t("В очереди уже 32 файла. Сначала подключи Mac."));
                    for (File file : existing) used += file.length();
                }
                String name = "file";
                long expected=-1;
                try (Cursor cursor = app.getContentResolver().query(uri, new String[] {OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE}, null, null, null)) {
                    if (cursor != null && cursor.moveToFirst()) { name = cursor.getString(0);if(!cursor.isNull(1))expected=cursor.getLong(1); }
                }
                if (name == null) name = "file";
                name = name.substring(0, Math.min(name.length(), 200));
                FileTransfers.begin(id,name,true,"",expected,FileTransfers.Phase.PREPARING);
                payload = new File(outbox, id); metadata = new File(index, id + ".json");
                long size = 0;
                try (InputStream input = app.getContentResolver().openInputStream(uri); OutputStream output = new FileOutputStream(payload)) {
                    if (input == null) throw new IOException(t("Не удалось открыть файл"));
                    byte[] buffer = new byte[65536]; int read;
                    while ((read = input.read(buffer)) != -1) {
                        size += read;
                        if (size > MAX || size + used > MAX) throw new IOException(t("Для очереди доступен 1 ГБ. Сначала передай остальные файлы."));
                        output.write(buffer, 0, read);
                    }
                }
                FileTransfers.total(id,size);FileTransfers.phase(id,FileTransfers.Phase.WAITING);
                JSONObject event = BridgeService.object("type", "file", "path", payload.getAbsolutePath(), "name", name, "size", size);
                try (OutputStream output = new FileOutputStream(metadata)) { output.write(event.toString().getBytes(StandardCharsets.UTF_8)); }
                BridgeService.emit(event);
                toast(app, BridgeService.client == null ? t("Файл в очереди. Подключи Conduit на Mac.") : t("Передаю файл на Mac"));
            } catch (Exception e) {
                FileTransfers.queued(id,"file",-1);
                FileTransfers.fail(id,e.getMessage()==null?t("Не удалось отправить файл"):e.getMessage());
                if (payload != null) payload.delete(); if (metadata != null) metadata.delete();
                toast(app, e.getMessage() == null ? t("Не удалось отправить файл") : e.getMessage());
            }
        });
    }
    static void sendPending(Context context) {
        Context app = context.getApplicationContext();
        BridgeService.IO.execute(() -> {
            File[] files = new File(app.getFilesDir(), "shares").listFiles();
            if (files == null) return;
            for (File file : files) {
                if (!file.getName().matches("[a-f0-9-]{36}\\.bin\\.json") || file.length() > 16384) continue;
                try {
                    JSONObject event=new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                    FileTransfers.queued(file.getName().substring(0,file.getName().length()-5),event.optString("name","file"),event.optLong("size",-1));
                    BridgeService.emit(event);
                }
                catch (Exception ignored) {}
            }
        });
    }
    static void acknowledge(Context context, String name) {
        if (!name.matches("[a-f0-9-]{36}\\.bin")) return;
        BridgeService.IO.execute(() -> {
            for(FileTransfers.Entry entry:FileTransfers.snapshot()) if(entry.id.equals(name) && entry.active()) {
                FileTransfers.progress(name,entry.total);FileTransfers.complete(name);
            }
            new File(new File(context.getExternalFilesDir(null), "outbox"), name).delete();
            new File(new File(context.getFilesDir(), "shares"), name + ".json").delete();
        });
    }
    private static void toast(Context context, String text) { new Handler(Looper.getMainLooper()).post(() -> Toast.makeText(context, text, Toast.LENGTH_LONG).show()); }
}
