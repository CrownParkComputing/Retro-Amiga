# SDLActivity's JNI table is registered by name from native code. Keep every
# declaration even when a release build is configured to shrink dependencies.
-keep class org.libsdl.app.** { *; }

# This app's own bridge classes. The core resolves their native methods by
# JNI symbol name (Java_com_uae4arm2026_...) and calls back into them by
# name, none of which R8 can see, so nothing here may be renamed or stripped.
-keep class com.uae4arm2026.** { *; }
