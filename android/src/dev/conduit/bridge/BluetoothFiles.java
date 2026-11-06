package dev.conduit.bridge;

import static dev.conduit.bridge.I18n.t;

import android.content.*;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.util.Base64;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Locale;

/** One upload and one download per authenticated RFCOMM peer. No arbitrary remote paths. */
final class BluetoothFiles {
    static final long MAX = 100L * 1024 * 1024;
    private final Context context;
    private final BridgeService.Endpoint peer;
    private String uploadID, downloadID, uploadName, expectedHash;
    private long uploadSize, written;
    private File temporary;
    private OutputStream upload;
    private MessageDigest hash;
    private RandomAccessFile download;
    BluetoothFiles(Context context, BridgeService.Endpoint peer) { this.context = context; this.peer = peer; }

    synchronized void handle(JSONObject event) {
        String id = event.optString("id"), type = event.optString("type");
        try {
            if ("fileBegin".equals(type)) {
                if (!BluetoothLink.validUUID(id) || upload != null) throw new IOException(t("Другая передача ещё не завершена"));
                long size = event.optLong("size", -1);
                String sha = event.optString("sha256");
                if (size < 0 || size > MAX || !sha.matches("[a-fA-F0-9]{64}")) throw new IOException(t("По Bluetooth — файлы до 100 МБ"));
                uploadID = id; uploadSize = size; written = 0; expectedHash = sha.toLowerCase(Locale.US);
                uploadName = safeName(event.optString("name", "file"));
                temporary = File.createTempFile("conduit-bt-", ".partial", context.getCacheDir());
                upload = new FileOutputStream(temporary); hash = MessageDigest.getInstance("SHA-256");
                reply("fileReady", id);
            } else if ("fileChunk".equals(type)) {
                if (upload == null || !id.equals(uploadID) || event.optLong("offset", -1) != written) throw new IOException(t("Неверный порядок частей файла"));
                String encoded = event.optString("data");
                if (encoded.length() > 22000) throw new IOException(t("Часть файла слишком велика"));
                byte[] data = Base64.decode(encoded, Base64.NO_WRAP);
                if (data.length == 0 || data.length > 16384 || data.length > uploadSize - written) throw new IOException(t("Неверный размер части файла"));
                upload.write(data); hash.update(data); written += data.length;
                BridgeService.emitTo(peer, BridgeService.object("type", "fileAck", "id", id, "offset", written));
            } else if ("fileEnd".equals(type)) {
                if (upload == null || !id.equals(uploadID) || written != uploadSize || !hex(hash.digest()).equals(expectedHash)) throw new IOException(t("Размер или SHA-256 файла не совпал"));
                upload.close(); upload = null;
                publish(temporary, id.substring(0, 8) + "_" + uploadName);
                temporary.delete(); temporary = null; uploadID = null;
                reply("fileDone", id);
            } else if ("fileAbort".equals(type)) {
                if (id.equals(uploadID)) abortUpload();
                if (id.equals(downloadID)) closeDownload();
            } else if ("fileGet".equals(type)) {
                if (!id.matches("[a-f0-9-]{36}\\.bin")) throw new IOException(t("Неверный идентификатор файла"));
                File file = new File(new File(context.getExternalFilesDir(null), "outbox"), id);
                if (!file.isFile() || file.length() > MAX) throw new IOException(t("Файл недоступен или больше 100 МБ"));
                File index = new File(new File(context.getFilesDir(), "shares"), id + ".json");
                if (index.length() > 16384) throw new IOException(t("Неверные сведения о файле"));
                JSONObject metadata = new JSONObject(new String(Files.readAllBytes(index.toPath()), StandardCharsets.UTF_8));
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                try (InputStream stream = new FileInputStream(file)) { byte[] b = new byte[65536]; int n; while ((n = stream.read(b)) != -1) digest.update(b, 0, n); }
                closeDownload(); download = new RandomAccessFile(file, "r"); downloadID = id;
                BridgeService.emitTo(peer, BridgeService.object("type", "fileInfo", "id", id, "size", file.length(), "name", metadata.optString("name", "file"), "sha256", hex(digest.digest())));
            } else if ("fileRead".equals(type)) {
                long offset = event.optLong("offset", -1);
                if (download == null || !id.equals(downloadID) || offset < 0 || offset >= download.length()) throw new IOException(t("Файл не открыт"));
                download.seek(offset);
                byte[] data = new byte[(int)Math.min(16384, download.length() - offset)]; download.readFully(data);
                BridgeService.emitTo(peer, BridgeService.object("type", "fileData", "id", id, "offset", offset, "data", Base64.encodeToString(data, Base64.NO_WRAP)));
            }
        } catch (Exception e) {
            if (id.equals(uploadID)) abortUpload();
            if (id.equals(downloadID)) closeDownload();
            BridgeService.emitTo(peer, BridgeService.object("type", "fileError", "id", id, "message", e.getMessage() == null ? t("Передача не завершена") : e.getMessage()));
        }
    }
    private void publish(File file, String name) throws IOException {
        if (Build.VERSION.SDK_INT >= 29) {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, name); values.put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream");
            values.put(MediaStore.Downloads.RELATIVE_PATH, "Download/Conduit"); values.put(MediaStore.Downloads.IS_PENDING, 1);
            ContentResolver resolver = context.getContentResolver();
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IOException(t("Не удалось сохранить файл в Загрузки"));
            try {
                try (InputStream input = new FileInputStream(file); OutputStream output = resolver.openOutputStream(uri)) {
                    if (output == null) throw new IOException(t("Хранилище недоступно"));
                    byte[] buffer = new byte[65536]; int n; while ((n = input.read(buffer)) != -1) output.write(buffer, 0, n);
                }
                values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0); resolver.update(uri, values, null, null);
            } catch (Exception e) { resolver.delete(uri, null, null); throw new IOException(t("Не удалось сохранить файл")); }
        } else {
            File dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
            if (dir == null || (!dir.isDirectory() && !dir.mkdirs())) throw new IOException(t("Хранилище недоступно"));
            try (InputStream input = new FileInputStream(file); OutputStream output = new FileOutputStream(new File(dir, name))) {
                byte[] buffer = new byte[65536]; int n; while ((n = input.read(buffer)) != -1) output.write(buffer, 0, n);
            }
        }
    }
    private void reply(String type, String id) { BridgeService.emitTo(peer, BridgeService.object("type", type, "id", id)); }
    private static String safeName(String name) {
        String value = name.replaceAll("[^\\p{L}\\p{N}._ -]", "_");
        return value.isEmpty() ? "file" : value.substring(0, Math.min(value.length(), 100));
    }
    static String hex(byte[] bytes) { StringBuilder s = new StringBuilder(); for (byte b : bytes) s.append(String.format(Locale.US, "%02x", b & 255)); return s.toString(); }
    private void abortUpload() {
        if (upload != null) try { upload.close(); } catch (IOException ignored) {}
        upload = null; uploadID = null;
        if (temporary != null) temporary.delete(); temporary = null;
    }
    private void closeDownload() { if (download != null) try { download.close(); } catch (IOException ignored) {} download = null; downloadID = null; }
    synchronized void received(String id) { if (id.equals(downloadID)) closeDownload(); }
    synchronized void close() { abortUpload(); closeDownload(); }
}
