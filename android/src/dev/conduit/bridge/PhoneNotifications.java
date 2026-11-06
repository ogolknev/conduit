package dev.conduit.bridge;

import android.app.*;
import android.content.*;
import android.os.*;
import android.provider.Settings;
import android.service.notification.*;
import java.util.*;

public final class PhoneNotifications extends NotificationListenerService {
    private static volatile PhoneNotifications instance;
    static boolean hasAccess(Context context) {
        String enabled = Settings.Secure.getString(context.getContentResolver(), "enabled_notification_listeners");
        if (enabled == null) return false;
        ComponentName own = new ComponentName(context, PhoneNotifications.class);
        for (String component : enabled.split(":")) if (own.equals(ComponentName.unflattenFromString(component))) return true;
        return false;
    }

    @Override public void onListenerConnected() { instance = this; BridgeService.emit(BridgeService.status("status")); }
    @Override public void onListenerDisconnected() { instance = null; BridgeService.emit(BridgeService.status("status")); }
    @Override public void onDestroy() { if (instance == this) instance = null; super.onDestroy(); }

    @Override public void onNotificationPosted(StatusBarNotification sbn) {
        try { forward(sbn); } catch (RuntimeException ignored) { /* Malformed app extras must not kill the listener. */ }
    }
    private void forward(StatusBarNotification sbn) {
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
        BridgeService.emit(BridgeService.object("type", "notification", "key", sbn.getKey(), "package", sbn.getPackageName(),
            "app", clipped(app, 128), "title", title, "body", body, "replyable", replyAction(n) != null));
    }
    @Override public void onNotificationRemoved(StatusBarNotification sbn) {
        if (sbn != null) BridgeService.emit(BridgeService.object("type", "removed", "key", sbn.getKey()));
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
    static void reply(String key, String text) {
        PhoneNotifications service = instance;
        if (service == null) { BridgeService.result(false, "Нет доступа к уведомлениям на телефоне"); return; }
        if (text.isEmpty() || text.length() > 4096) return;
        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                StatusBarNotification[] notifications = service.getActiveNotifications(new String[] { key });
                if (notifications == null || notifications.length == 0) throw new IllegalStateException();
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
                BridgeService.result(true, "Ответ отправлен");
            } catch (Exception e) { BridgeService.result(false, "Уведомление больше не принимает ответ"); }
        });
    }
    static void dismiss(String key) {
        PhoneNotifications service = instance;
        if (service != null) new Handler(Looper.getMainLooper()).post(() -> {
            try { service.cancelNotification(key); } catch (Exception ignored) {}
        });
    }
}
