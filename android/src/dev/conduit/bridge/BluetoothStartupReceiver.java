package dev.conduit.bridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Restore only a connection the user previously enabled, after supported system events. */
public final class BluetoothStartupReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction()) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(intent.getAction())) {
            PhoneDiagnostics.record(context, Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction()) ? "service.restore.boot" : "service.restore.update");
            BridgeService.restoreIfWanted(context);
        }
    }
}
