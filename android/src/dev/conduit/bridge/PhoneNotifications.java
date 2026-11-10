package dev.conduit.bridge;

import static dev.conduit.bridge.I18n.t;

import android.app.*;
import android.content.*;
import android.os.*;
import android.provider.Settings;
import android.service.notification.*;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import android.util.LruCache;
import java.io.ByteArrayOutputStream;
import java.util.*;
import org.json.JSONObject;

public final class PhoneNotifications extends NotificationListenerService {
    private static volatile PhoneNotifications instance;
    private final LruCache<String,String> icons=new LruCache<>(40);
    private static long lastRebind;
    private static boolean registrationRefreshed;
    static boolean isConnected() { return instance!=null; }
    static void ensureConnected(Context context) {
        long now=SystemClock.elapsedRealtime();
        if(instance!=null || !hasAccess(context) || now-lastRebind<15000) return;
        lastRebind=now;
        try {
            ComponentName component=new ComponentName(context,PhoneNotifications.class);
            if(!registrationRefreshed) {
                registrationRefreshed=true;
                android.content.pm.PackageManager pm=context.getPackageManager();
                int state=pm.getComponentEnabledSetting(component);
                // Both states leave this manifest-enabled service enabled. The package-change
                // broadcast makes Android rescan its stale listener registration after an update.
                if(state==android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DEFAULT || state==android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                    pm.setComponentEnabledSetting(component,state==android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ? android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED : android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,android.content.pm.PackageManager.DONT_KILL_APP);
                    PhoneDiagnostics.record(context,"notification.listener.registration.refreshed");
                }
            }
            requestRebind(component); PhoneDiagnostics.record(context,"notification.listener.rebind");
        }
        catch(RuntimeException failure) { PhoneDiagnostics.record(context,"notification.listener.failed",failure); }
    }
    static boolean hasAccess(Context context) {
        if(Build.VERSION.SDK_INT>=27) return context.getSystemService(NotificationManager.class).isNotificationListenerAccessGranted(new ComponentName(context,PhoneNotifications.class));
        String enabled = Settings.Secure.getString(context.getContentResolver(), "enabled_notification_listeners");
        if (enabled == null) return false;
        ComponentName own = new ComponentName(context, PhoneNotifications.class);
        for (String component : enabled.split(":")) if (own.equals(ComponentName.unflattenFromString(component))) return true;
        return false;
    }

    @Override public void onListenerConnected() { instance = this; PhoneDiagnostics.record(this,"notification.listener.connected"); BridgeService.emit(BridgeService.status("status")); }
    @Override public void onListenerDisconnected() { instance = null; PhoneDiagnostics.record(this,"notification.listener.disconnected"); BridgeService.emit(BridgeService.status("status")); }
    @Override public void onDestroy() { if (instance == this) instance = null; super.onDestroy(); }

    @Override public void onNotificationPosted(StatusBarNotification sbn) {
        try { forward(sbn); } catch (RuntimeException ignored) { /* Malformed app extras must not kill the listener. */ }
    }
    private void forward(StatusBarNotification sbn) { forward(sbn, BridgeService.client, null); }
    private void forward(StatusBarNotification sbn, BridgeService.Endpoint target, String snapshot) {
        if (sbn == null || sbn.getPackageName().equals(getPackageName())) return;
        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);
        if (!prefs.getBoolean("forward", true) || prefs.getStringSet("blocked", Collections.emptySet()).contains(sbn.getPackageName())) return;
        Notification n = sbn.getNotification();
        if ((n.flags & Notification.FLAG_GROUP_SUMMARY) != 0 || sbn.isOngoing()) return;
        Bundle extras = n.extras;
        if (extras == null) return;
        String title = clipped(extras.getCharSequence(Notification.EXTRA_TITLE), 256);
        CharSequence bodyValue = extras.getCharSequence(Notification.EXTRA_BIG_TEXT);
        if (bodyValue == null) bodyValue = extras.getCharSequence(Notification.EXTRA_TEXT);
        String body = clipped(bodyValue, 4096);
        String app = sbn.getPackageName();
        try { app = getPackageManager().getApplicationLabel(getPackageManager().getApplicationInfo(app, 0)).toString(); } catch (Exception ignored) {}
        if (title.isEmpty() && body.isEmpty()) return;
        BridgeService.emitTo(target, BridgeService.object("type", "notification", "instance", Long.toString(sbn.getPostTime()), "dismissible", sbn.isClearable(), "snapshot", snapshot, "key", sbn.getKey(), "package", sbn.getPackageName(),
            "app", clipped(app, 128), "title", title, "body", body, "replyable", replyAction(n) != null, "iconPNG", applicationIcon(sbn.getPackageName())));
    }
    private String applicationIcon(String pkg) {
        Bitmap bitmap=null;
        try {
            String key=pkg+":"+getPackageManager().getPackageInfo(pkg,0).lastUpdateTime;
            String cached=icons.get(key); if(cached!=null) return cached;
            Drawable drawable=getPackageManager().getApplicationIcon(pkg);
            bitmap=Bitmap.createBitmap(64,64,Bitmap.Config.ARGB_8888); drawable.setBounds(0,0,64,64); drawable.draw(new Canvas(bitmap));
            ByteArrayOutputStream bytes=new ByteArrayOutputStream(); bitmap.compress(Bitmap.CompressFormat.PNG,100,bytes);
            if(bytes.size()>32768) return "";
            String encoded=Base64.encodeToString(bytes.toByteArray(),Base64.NO_WRAP); icons.put(key,encoded); return encoded;
        } catch(Exception failure) { return ""; }
        finally { if(bitmap!=null) bitmap.recycle(); }
    }
    @Override public void onNotificationRemoved(StatusBarNotification sbn) {
        if (sbn != null) BridgeService.emit(BridgeService.object("type", "removed", "key", sbn.getKey(), "instance", Long.toString(sbn.getPostTime())));
    }
    private static String clipped(CharSequence value, int size) {
        if (value == null) return "";
        String text = value.toString();
        return text.length() <= size ? text : text.substring(0, size);
    }
    private static Notification.Action replyAction(Notification notification) {
        if (notification.actions == null) return null;
        for (Notification.Action action : notification.actions) {
            RemoteInput[] inputs = action.getRemoteInputs();
            if (inputs != null && action.actionIntent != null)
                for (RemoteInput input : inputs) if (input.getAllowFreeFormInput()) return action;
        }
        return null;
    }
    static void reply(String key, String text, String version, BridgeService.Endpoint target, String request) {
        PhoneNotifications service = instance;
        if (service == null) { replyResult(target, request, false, t("Нет доступа к уведомлениям на телефоне")); return; }
        if (text.isEmpty() || text.length() > 4096) return;
        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                if (BridgeService.client != target) return;
                StatusBarNotification[] notifications = service.getActiveNotifications(new String[] { key });
                if (notifications == null || notifications.length == 0 || (!version.isEmpty() && !Long.toString(notifications[0].getPostTime()).equals(version))) throw new IllegalStateException();
                String pkg = notifications[0].getPackageName();
                SharedPreferences prefs = service.getSharedPreferences("settings", MODE_PRIVATE);
                if (!prefs.getBoolean("forward", true) || prefs.getStringSet("blocked", Collections.emptySet()).contains(pkg)) throw new IllegalStateException();
                Notification.Action action = replyAction(notifications[0].getNotification());
                if (action == null) throw new IllegalStateException();
                Bundle values = new Bundle();
                for (RemoteInput input : action.getRemoteInputs()) if (input.getAllowFreeFormInput()) values.putCharSequence(input.getResultKey(), text);
                Intent fill = new Intent();
                RemoteInput.addResultsToIntent(action.getRemoteInputs(), fill, values);
                action.actionIntent.send(service, 0, fill);
                replyResult(target, request, true, t("Ответ отправлен"));
            } catch (Exception e) { replyResult(target, request, false, t("Уведомление больше не принимает ответ")); }
        });
    }
    private static void replyResult(BridgeService.Endpoint target, String request, boolean ok, String message) {
        BridgeService.emitTo(target, BridgeService.object("type", request.isEmpty() ? "result" : "notificationReplyResult", "request", request, "ok", ok, "message", message));
    }
    static synchronized String source(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", MODE_PRIVATE);
        String id = prefs.getString("notificationSource", null);
        if (id == null) { id = UUID.randomUUID().toString(); prefs.edit().putString("notificationSource", id).commit(); }
        return id;
    }
    static void snapshot(BridgeService.Endpoint target, String request) {
        if (request.length() > 64) return;
        new Handler(Looper.getMainLooper()).post(() -> {
            if (BridgeService.client != target) return;
            PhoneNotifications service = instance;
            boolean ok = false;
            try {
                if (service != null) {
                    StatusBarNotification[] active = service.getActiveNotifications();
                    if (active != null && active.length <= 500) {
                        for (StatusBarNotification item : active) service.forward(item, target, request);
                        ok = true;
                    }
                }
            } catch (RuntimeException ignored) {}
            BridgeService.emitTo(target, BridgeService.object("type", "notificationSnapshotEnd", "request", request, "ok", ok));
        });
    }
    static void dismissTracked(BridgeService.Endpoint target, String key, String version) {
        if (key.length() > 2048 || version.length() > 64) return;
        new Handler(Looper.getMainLooper()).post(() -> {
            if (BridgeService.client != target) return;
            PhoneNotifications service = instance;
            try {
                if (service == null) throw new IllegalStateException();
                StatusBarNotification[] active = service.getActiveNotifications(new String[] {key});
                if (active == null) throw new IllegalStateException();
                if (active.length == 0 || !Long.toString(active[0].getPostTime()).equals(version)) {
                    dismissResult(target, key, version, true); return;
                }
                SharedPreferences prefs = service.getSharedPreferences("settings", MODE_PRIVATE);
                if (!active[0].isClearable() || !prefs.getBoolean("forward", true) || prefs.getStringSet("blocked", Collections.emptySet()).contains(active[0].getPackageName())) throw new IllegalStateException();
                service.cancelNotification(key);
                new Handler(Looper.getMainLooper()).postDelayed(() -> {
                    if (BridgeService.client != target) return;
                    boolean removed = false;
                    try {
                        if (instance != service) throw new IllegalStateException();
                        StatusBarNotification[] remaining = service.getActiveNotifications(new String[] {key});
                        removed = remaining != null && (remaining.length == 0 || !Long.toString(remaining[0].getPostTime()).equals(version));
                    } catch (RuntimeException ignored) {}
                    dismissResult(target, key, version, removed);
                }, 1000);
            } catch (RuntimeException failure) { dismissResult(target, key, version, false); }
        });
    }
    private static void dismissResult(BridgeService.Endpoint target, String key, String version, boolean ok) {
        BridgeService.emitTo(target, BridgeService.object("type", "notificationDismissed", "key", key, "instance", version, "ok", ok));
    }
    static void dismiss(String key) {
        PhoneNotifications service = instance;
        if (service != null) new Handler(Looper.getMainLooper()).post(() -> {
            try { service.cancelNotification(key); } catch (Exception ignored) {}
        });
    }
}
