package com.byrafael.streamapp;

import java.nio.charset.StandardCharsets;

/**
 * Compatibility wrapper for Rafael's authorized Fútbol Total native signer.
 * The native library is supplied only in the isolated test build.
 */
public final class Guard {
    static {
        System.loadLibrary("guard");
    }

    private native String nativeSign(byte[] certDigest, byte[] message);
    private native String nativeDec(byte[] certDigest, byte[] payload);

    public String sign(byte[] certDigest, String message) {
        if (certDigest == null || certDigest.length == 0 || message == null) return "";
        try {
            return nativeSign(certDigest, message.getBytes(StandardCharsets.UTF_8));
        } catch (Throwable ignored) {
            return "";
        }
    }
}
