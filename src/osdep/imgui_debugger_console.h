#pragma once

/*
 * Debugger console shim.
 *
 * Upstream Amiberry hosts the debugger console in its ImGui GUI and declares
 * these on the desktop platforms that build it. This fork has no ImGui on any
 * platform, so every entry point is an inline no-op reporting "unsupported"
 * and the compiler folds the calls away. Debug output still reaches the log
 * via write_log().
 */

inline bool imgui_debugger_console_supported() { return false; }
inline void imgui_debugger_console_open() {}
inline void imgui_debugger_console_close() {}
inline void imgui_debugger_console_activate() {}
inline void imgui_debugger_console_write(const char*) {}
inline bool imgui_debugger_console_has_input() { return false; }
inline char imgui_debugger_console_getch() { return 0; }
inline int imgui_debugger_console_get(char*, int) { return -1; }
