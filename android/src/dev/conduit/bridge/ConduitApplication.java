package dev.conduit.bridge;

import android.app.Application;

public final class ConduitApplication extends Application {
    @Override public void onCreate() {
        super.onCreate(); PhoneDiagnostics.record(this, "process.start");
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, failure) -> {
            try { PhoneDiagnostics.record(this, "process.crash", failure); }
            catch (Throwable ignored) { }
            finally { if (previous != null) previous.uncaughtException(thread, failure); }
        });
    }
}
