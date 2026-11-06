package dev.conduit.bridge;

import java.nio.charset.StandardCharsets;

/** Diagnostics must never serialize Throwable messages, which can contain user data. */
final class DiagnosticText {
    static String failure(Throwable error) {
        StringBuilder text = new StringBuilder();
        for (int cause = 0; error != null && cause < 3; cause++, error = error.getCause()) {
            text.append(cause == 0 ? " error=" : " causedBy=").append(error.getClass().getName());
            StackTraceElement[] frames = error.getStackTrace();
            for (int i = 0; i < Math.min(frames.length, 8); i++) {
                StackTraceElement frame = frames[i];
                text.append("\n  at ").append(frame.getClassName()).append('.').append(frame.getMethodName()).append(':').append(frame.getLineNumber());
            }
        }
        return text.toString();
    }
    static String tail(String text, int maxBytes) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (bytes.length <= maxBytes) return text;
        int start = bytes.length - maxBytes;
        while (start < bytes.length && bytes[start] != '\n') start++;
        return start < bytes.length ? new String(bytes, start + 1, bytes.length - start - 1, StandardCharsets.UTF_8) : "";
    }
}
