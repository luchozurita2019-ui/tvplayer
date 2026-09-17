package com.titan.ranger;

/**
 * Puente JNI mínimo para la rama forense Lista TV 3.
 *
 * La implementación nativa no se distribuye con TV FULL: XuperRangerBridge la
 * carga desde la instalación local de Xuper en el mismo dispositivo.
 */
public final class NativeJni {
    private static final NativeJni INSTANCE = new NativeJni();

    private NativeJni() {}

    private native String Call(String command, String data);

    public static NativeJni getInstance() {
        return INSTANCE;
    }

    public synchronized String call(String command, String data) {
        return Call(command, data);
    }
}
