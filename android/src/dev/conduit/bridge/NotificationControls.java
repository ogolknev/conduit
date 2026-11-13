package dev.conduit.bridge;

import android.app.KeyguardManager;
import android.app.Notification;
import android.app.PendingIntent;
import android.content.Context;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.service.notification.StatusBarNotification;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;

/** Descriptions cross the wire. Intents and media sessions stay on the phone. */
final class NotificationControls {
    final String id, label;
    private final PendingIntent intent;
    private final boolean needsUnlock;
    private final Runnable mediaCommand;

    private NotificationControls(String id, String label, PendingIntent intent, boolean needsUnlock, Runnable command) {
        this.id = id;
        this.label = label;
        this.intent = intent;
        this.needsUnlock = needsUnlock;
        this.mediaCommand = command;
    }

    static MediaController controller(Context context, StatusBarNotification item) {
        if (Build.VERSION.SDK_INT < 33) return null;
        Notification notification = item.getNotification();
        MediaSession.Token token = notification.extras.getParcelable(Notification.EXTRA_MEDIA_SESSION, MediaSession.Token.class);
        if (token == null) return null;
        try {
            if (context.getPackageManager().getApplicationInfo(item.getPackageName(), 0).targetSdkVersion < 33) return null;
            MediaController controller = new MediaController(context, token);
            return item.getPackageName().equals(controller.getPackageName()) ? controller : null;
        } catch (Exception unavailable) { return null; }
    }

    static List<NotificationControls> available(Notification notification, MediaController controller) {
        List<NotificationControls> controls = new ArrayList<>();
        PlaybackState state = controller == null ? null : controller.getPlaybackState();
        if (state != null) {
            MediaController.TransportControls transport = controller.getTransportControls();
            long actions = state.getActions();
            if ((actions & PlaybackState.ACTION_SKIP_TO_PREVIOUS) != 0)
                media(controls, "previous", "", transport::skipToPrevious);
            int playback = state.getState();
            boolean paused = playback == PlaybackState.STATE_PAUSED || playback == PlaybackState.STATE_NONE
                    || playback == PlaybackState.STATE_STOPPED || playback == PlaybackState.STATE_ERROR;
            if (paused && (actions & (PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PLAY_PAUSE)) != 0)
                media(controls, "play", "", transport::play);
            if (!paused && playback != PlaybackState.STATE_BUFFERING && playback != PlaybackState.STATE_CONNECTING
                    && (actions & (PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE)) != 0)
                media(controls, "pause", "", transport::pause);
            if ((actions & PlaybackState.ACTION_SKIP_TO_NEXT) != 0)
                media(controls, "next", "", transport::skipToNext);
            for (PlaybackState.CustomAction custom : state.getCustomActions()) {
                if (controls.size() >= 5) break;
                String key = custom.getAction();
                if (key != null && key.length() <= 160 && custom.getName() != null)
                    media(controls, "custom:" + key, title(custom.getName()), () -> transport.sendCustomAction(custom, custom.getExtras()));
            }
            return controls;
        }
        if (notification.actions == null) return controls;
        for (int i = 0; i < notification.actions.length && controls.size() < 8; i++) {
            Notification.Action action = notification.actions[i];
            if (action == null || action.actionIntent == null || action.getRemoteInputs() != null
                    || action.getDataOnlyRemoteInputs() != null || action.title == null) continue;
            String label = title(action.title);
            if (!label.isEmpty()) controls.add(new NotificationControls("action:" + i, label, action.actionIntent,
                    Build.VERSION.SDK_INT >= 31 && action.isAuthenticationRequired(), null));
        }
        return controls;
    }

    private static String title(CharSequence value) {
        String s = value.toString().trim();
        return s.substring(0, Math.min(s.length(), 100));
    }
    private static void media(List<NotificationControls> controls, String id, String label, Runnable command) {
        controls.add(new NotificationControls(id, label, null, false, command));
    }
    static JSONArray describe(List<NotificationControls> controls) {
        JSONArray result = new JSONArray();
        for (NotificationControls control : controls)
            result.put(BridgeService.object("id", control.id, "label", control.label));
        return result;
    }
    void perform(Context context) throws PendingIntent.CanceledException {
        if (needsUnlock && context.getSystemService(KeyguardManager.class).isDeviceLocked()) throw new IllegalStateException();
        if (intent != null) intent.send();
        else mediaCommand.run();
    }
}
