package dev.conduit.bridge;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

public final class DiagnosticTextTest {
    public static void main(String[] args) {
        Throwable failure = new IOException("SECRET_CLIPBOARD_123", new IllegalStateException("SECRET_NOTIFICATION_456"));
        String trace = DiagnosticText.failure(failure);
        if (trace.contains("SECRET") || !trace.contains("IOException") || !trace.contains("IllegalStateException") || !trace.contains("DiagnosticTextTest.main")) throw new AssertionError(trace);
        String log = "";
        for (int i = 0; i < 300; i++) log += "event " + i + " Кириллица 😀\n";
        String tail = DiagnosticText.tail(log, 600);
        if (tail.getBytes(StandardCharsets.UTF_8).length > 600 || !tail.endsWith("299 Кириллица 😀\n") || tail.contains("�")) throw new AssertionError("Invalid bounded UTF-8 tail");
        if (!DiagnosticText.tail("small\n", 100).equals("small\n")) throw new AssertionError("Short log changed");
        System.out.println("Diagnostic privacy, stack, UTF-8 and size checks passed");
    }
}
