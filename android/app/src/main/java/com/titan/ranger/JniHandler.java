package com.titan.ranger;

import org.json.JSONObject;

/**
 * Callback mínimo esperado por libranger-jni.so.
 *
 * Conserva únicamente el último Status recibido por OnPrepareEvent para que
 * TV FULL pueda recuperar play_url/host/format y seguir reproduciendo con
 * Media3. Los otros callbacks se reconocen y responden éxito, pero no controlan
 * el reproductor de TV FULL.
 */
public final class JniHandler {
    private static volatile String lastEvent = "";
    private static volatile String lastStatus = "";
    private static volatile long lastErr = 0L;

    public JniHandler() {}

    public static void clearPrepareStatus() {
        lastEvent = "";
        lastStatus = "";
        lastErr = 0L;
    }

    public static String getLastEvent() {
        return lastEvent;
    }

    public static String getLastStatus() {
        return lastStatus;
    }

    public static long getLastErr() {
        return lastErr;
    }

    @SuppressWarnings("unused")
    private String Callback(String command, String data) {
        try {
            if ("OnPrepareEvent".equals(command) && data != null && !data.isEmpty()) {
                final JSONObject payload = new JSONObject(data);
                lastEvent = payload.optString("event", "");
                lastStatus = payload.optString("status", "");
                lastErr = payload.optLong("err", 0L);
            }
            return new JSONObject().put("err", 0).put("res", "").toString();
        } catch (Throwable error) {
            try {
                return new JSONObject().put("err", 22).put("res", "").toString();
            } catch (Throwable ignored) {
                return "{\"err\":22,\"res\":\"\"}";
            }
        }
    }
}
