package dev.conduit.bridge;

/** Effective channel/ranking policy, separate from transport replay suppression. */
final class NotificationAlertPolicy {
    final boolean banner, sound;
    NotificationAlertPolicy(int importance, boolean matchesFilter, boolean peekSuppressed,
            boolean hasSound, boolean audioAllowed, boolean groupSilenced, boolean onlyOnceUpdate) {
        boolean alert = !groupSilenced && !onlyOnceUpdate;
        banner = alert && importance >= 4 && !peekSuppressed;
        sound = alert && importance >= 3 && matchesFilter && hasSound && audioAllowed;
    }
}
