package dev.conduit.bridge;

public final class NotificationAlertPolicyTest {
    private static void check(NotificationAlertPolicy policy, boolean banner, boolean sound) {
        if (policy.banner != banner || policy.sound != sound) throw new AssertionError();
    }
    public static void main(String[] args) {
        check(new NotificationAlertPolicy(4, true, false, true, true, false, false), true, true);
        check(new NotificationAlertPolicy(4, true, false, false, true, false, false), true, false);
        check(new NotificationAlertPolicy(3, true, false, true, true, false, false), false, true);
        check(new NotificationAlertPolicy(2, true, false, true, true, false, false), false, false);
        check(new NotificationAlertPolicy(0, true, false, true, true, false, false), false, false);
        check(new NotificationAlertPolicy(4, false, true, true, true, false, false), false, false);
        check(new NotificationAlertPolicy(4, false, false, true, true, false, false), true, false); // DND can suppress sound independently.
        check(new NotificationAlertPolicy(4, true, true, true, true, false, false), false, true);
        check(new NotificationAlertPolicy(4, true, false, true, false, false, false), true, false); // Vibrate/mute/zero volume.
        check(new NotificationAlertPolicy(4, true, false, true, true, true, false), false, false);
        check(new NotificationAlertPolicy(4, true, false, true, true, false, true), false, false);
        System.out.println("Notification alerts: four banner/sound combinations, importance, DND, mute, groups and only-once updates passed");
    }
}
