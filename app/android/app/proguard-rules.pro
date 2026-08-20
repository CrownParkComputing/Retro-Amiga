# SDLActivity's JNI table is registered by name from native code. Keep every
# declaration even when a release build is configured to shrink dependencies.
-keep class org.libsdl.app.** { *; }
