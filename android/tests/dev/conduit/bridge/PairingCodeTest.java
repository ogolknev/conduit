package dev.conduit.bridge;
import java.security.SecureRandom;
import java.util.concurrent.atomic.AtomicLong;

public final class PairingCodeTest {
    private static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        AtomicLong now = new AtomicLong(0);
        SecureRandom random = new SecureRandom() { @Override public int nextInt(int bound) { return 12345678; } };
        PairingCode code = new PairingCode(now::get, random);
        check(code.display().isEmpty());
        check(code.open().equals("12345678")); check(code.verify("12345678")); check(!code.verify("12345678"));
        code.open(); check(!code.verify("00000000")); check(!code.verify("00000000")); check(!code.verify("00000000")); check(!code.verify("12345678"));
        code.open(); now.set(120000); check(code.display().isEmpty()); check(!code.verify("12345678"));
        now.set(0); code.open(); check(!code.verify("１２３４５６７８")); check(!code.verify("12345678\n")); check(!code.verify(null));
        code.close(); check(!code.verify("12345678")); check(code.display().isEmpty());
        System.out.println("PairingCode: one-use, expiry, three-attempt lockout, ASCII and revocation checks passed");
    }
}
