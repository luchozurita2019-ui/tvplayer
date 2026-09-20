package com.byrafael.streamapp;

import android.util.Base64;
import java.nio.charset.StandardCharsets;

/**
 * Copia funcional de la clase Guard observada en FT 3.6.
 * Mantiene los mismos nombres de campos/metodos JNI que espera libguard.so.
 */
public final class Guard {
    public static final Guard a = new Guard();
    public static volatile byte[] b;
    public static volatile boolean c;
    public static volatile boolean d;

    private native String nativeDec(byte[] certDigest, byte[] payload);
    private native String nativeSign(byte[] certDigest, byte[] message);

    public String a(String encoded) {
        byte[] cert = b;
        if (cert == null || !c) return "";
        try {
            return nativeDec(cert, Base64.decode(encoded, Base64.NO_WRAP));
        } catch (Throwable ignored) {
            return "";
        }
    }

    public String b(String message) {
        byte[] cert = b;
        if (cert == null || !c || message == null) return "";
        try {
            return nativeSign(cert, message.getBytes(StandardCharsets.UTF_8));
        } catch (Throwable ignored) {
            return "";
        }
    }
}
