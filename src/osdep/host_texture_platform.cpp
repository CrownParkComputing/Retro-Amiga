/*
 * The platform half of host_texture.h.
 *
 * Deliberately empty on every platform now. The two implementations of the
 * sink each live next to the host that drives them:
 *
 *   * Android: native/amigatexture/amigatexture.cpp, a library of its own.
 *     It owns the JNI entry points and reaches the running core's
 *     uae4arm_host_* symbols through dlopen/dlsym -- necessary because two
 *     cores in one process export the same symbol names, and JNI's lazy
 *     binding cannot be trusted to pick the right one.
 *
 *   * Apple: written in Swift against CVPixelBuffer and FlutterTexture, and
 *     installs itself through the same plain-C uae4arm_host_texture_set_sink.
 *
 * Everywhere else the launcher falls back to copy-and-decode.
 */

/* ISO C++ forbids an empty translation unit. */
extern "C" void uae4arm_host_texture_platform_unused(void);
void uae4arm_host_texture_platform_unused(void) {}
