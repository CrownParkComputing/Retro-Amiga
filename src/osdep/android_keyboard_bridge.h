#pragma once

/* Installs the Android implementations of uae4arm_host_callbacks. A no-op on
 * every other platform, so callers need no platform guard. */
void android_install_host_callbacks();
