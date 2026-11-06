package dev.conduit.bridge;

import java.security.MessageDigest;
import java.security.SecureRandom;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.function.LongSupplier;

final class PairingCode {
    private final LongSupplier clock;
    private final SecureRandom random;
    private String code = "";
    private long expires;
    private int attempts;
    PairingCode(LongSupplier clock, SecureRandom random) { this.clock = clock; this.random = random; }
    synchronized String open() {
        code = String.format(Locale.US, "%08d", random.nextInt(100_000_000));
        expires = clock.getAsLong() + 120_000; attempts = 0; return code;
    }
    synchronized String display() { return clock.getAsLong() < expires && attempts < 3 ? code : ""; }
    synchronized void close() { code = ""; expires = 0; attempts = 3; }
    synchronized boolean verify(String supplied) {
        if (display().isEmpty() || supplied == null || !supplied.matches("[0-9]{8}")) return false;
        attempts++;
        boolean ok = MessageDigest.isEqual(code.getBytes(StandardCharsets.US_ASCII), supplied.getBytes(StandardCharsets.US_ASCII));
        if (ok) { code = ""; expires = 0; }
        return ok;
    }
}
