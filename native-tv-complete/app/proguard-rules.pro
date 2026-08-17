-keepattributes *Annotation*
-dontwarn org.conscrypt.**
-keep class androidx.media3.** { *; }

# IJKPlayer Java classes contain JNI entry points referenced by the native
# libraries. Keep the bridge stable when R8 minifies the release APK.
-keep class tv.danmaku.ijk.media.player.** { *; }
-keep interface tv.danmaku.ijk.media.player.** { *; }
-dontwarn tv.danmaku.ijk.media.player.**
