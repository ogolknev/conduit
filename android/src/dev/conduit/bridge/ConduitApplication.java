package dev.conduit.bridge;

import android.app.Application;
import android.content.Context;
import android.content.res.Configuration;

public final class ConduitApplication extends Application {
    @Override protected void attachBaseContext(Context base) { super.attachBaseContext(I18n.wrap(base)); }
    @Override public void onConfigurationChanged(Configuration configuration) {
        super.onConfigurationChanged(configuration); I18n.refresh(this);
    }
    @Override public void onCreate() {
        super.onCreate(); I18n.refresh(this); PhoneDiagnostics.record(this, "process.start");
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, failure) -> {
            try { PhoneDiagnostics.record(this, "process.crash", failure); }
            catch (Throwable ignored) { }
            finally { if (previous != null) previous.uncaughtException(thread, failure); }
        });
    }
}
