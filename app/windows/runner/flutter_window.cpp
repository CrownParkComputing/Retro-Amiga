#include "flutter_window.h"

#include <windows.h>

#include <filesystem>
#include <string>
#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

using HostRun = int (*)(int, char**);
using MusicPlay = bool (*)(const char*);
using MusicStop = void (*)();
using MusicSetPaused = void (*)(bool);
using MusicIsBool = bool (*)();
using MusicTitle = const char* (*)();
using MusicLevel = float (*)();
using MusicSetVolume = void (*)(float);
HMODULE core_module = nullptr;

std::string AppSupportDirectory();

HostRun LoadCoreRun() {
  if (core_module == nullptr) {
    wchar_t executable[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameW(nullptr, executable, MAX_PATH);
    std::filesystem::path path(executable, executable + length);
    path = path.parent_path() / L"uae4arm.dll";
    core_module = LoadLibraryW(path.c_str());
    if (core_module == nullptr) return nullptr;
  }
  return reinterpret_cast<HostRun>(GetProcAddress(core_module, "uae4arm_host_run"));
}

template <typename Function>
Function CoreSymbol(const char* name) {
  if (LoadCoreRun() == nullptr) return nullptr;
  return reinterpret_cast<Function>(GetProcAddress(core_module, name));
}

std::string ReadEnvironmentPath(const wchar_t* name, const wchar_t* fallback) {
  const DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) {
    return fallback != nullptr ? Utf8FromUtf16(fallback) : "";
  }

  std::wstring wide(size, 0);
  const DWORD actual = GetEnvironmentVariableW(name, wide.data(), size);
  if (actual == 0) {
    return fallback != nullptr ? Utf8FromUtf16(fallback) : "";
  }

  wide.resize(actual);
  return Utf8FromUtf16(wide.c_str());
}

std::string AppSupportDirectory() {
  const std::string base = ReadEnvironmentPath(L"LOCALAPPDATA", L"C:\\");
  return (std::filesystem::path(base) / "uae4arm2026").string();
}

std::string DocumentsDirectory() {
  const std::string base = ReadEnvironmentPath(L"USERPROFILE", L"C:\\");
  return (std::filesystem::path(base) / "Documents").string();
}

std::string EmulatorHomeDirectory() {
  return (std::filesystem::path(DocumentsDirectory()) / "Amiberry").string();
}

std::string AppBuildStamp() {
  wchar_t module_path[MAX_PATH + 1] = {};
  const DWORD len = GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return "0";

  HANDLE exe_file = CreateFileW(
      module_path,
      GENERIC_READ,
      FILE_SHARE_READ,
      nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (exe_file == INVALID_HANDLE_VALUE) return "0";

  FILETIME write_time{};
  if (!GetFileTime(exe_file, nullptr, nullptr, &write_time)) {
    CloseHandle(exe_file);
    return "0";
  }
  CloseHandle(exe_file);

  ULARGE_INTEGER time_union{};
  time_union.LowPart = write_time.dwLowDateTime;
  time_union.HighPart = write_time.dwHighDateTime;

  constexpr uint64_t windows_epoch = 116444736000000000ULL;
  if (time_union.QuadPart <= windows_epoch) return "0";
  return std::to_string((time_union.QuadPart - windows_epoch) / 10000000ULL);
}

}  // namespace

static const char kMethodChannel[] = "uae4arm2026/emulator";

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  emulator_method_channel_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMethodChannel,
          &flutter::StandardMethodCodec::GetInstance());
  emulator_method_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string method = call.method_name();
        if (method == "platformName") {
          result->Success(EncodableValue("windows"));
        } else if (method == "appSupportDirectory") {
          result->Success(EncodableValue(AppSupportDirectory()));
        } else if (method == "documentsDirectory") {
          result->Success(EncodableValue(DocumentsDirectory()));
        } else if (method == "emulatorHomeDirectory") {
          result->Success(EncodableValue(EmulatorHomeDirectory()));
        } else if (method == "appBuildStamp") {
          result->Success(EncodableValue(AppBuildStamp()));
        } else if (method == "hasAllFilesAccess" ||
                   method == "requestAllFilesAccess") {
          result->Success(EncodableValue(true));
        } else if (method == "openControllerMapping") {
          result->Success(EncodableValue(false));
        } else if (method == "launch") {
          // No native game window any more: the machine renders inside the
          // Flutter panel via the in-process FFI core on every platform.
          result->Error("launch_failed",
                        "The emulator core could not be loaded (uae4arm.dll).");
        } else if (method == "musicPlay") {
          const auto* map = std::get_if<EncodableMap>(call.arguments());
          const std::string* text = nullptr;
          if (map != nullptr) {
            auto path = map->find(EncodableValue(std::string("path")));
            if (path != map->end()) text = std::get_if<std::string>(&path->second);
          }
          MusicPlay play = CoreSymbol<MusicPlay>("uae4arm_host_music_play");
          result->Success(EncodableValue(play != nullptr && text != nullptr && play(text->c_str())));
        } else if (method == "musicStop" || method == "musicReleaseAudio" ||
                   method == "musicSetPaused" ||
                   method == "musicSetVolume") {
          if (method == "musicStop") {
            if (MusicStop stop = CoreSymbol<MusicStop>("uae4arm_host_music_stop")) stop();
          } else if (method == "musicReleaseAudio") {
            if (MusicStop release = CoreSymbol<MusicStop>("uae4arm_host_music_release_audio"))
              release();
          } else if (method == "musicSetPaused") {
            const auto* map = std::get_if<EncodableMap>(call.arguments());
            if (map != nullptr) {
              auto found = map->find(EncodableValue(std::string("paused")));
              if (found != map->end()) {
                if (MusicSetPaused set = CoreSymbol<MusicSetPaused>("uae4arm_host_music_set_paused"))
                  if (const auto* paused = std::get_if<bool>(&found->second)) set(*paused);
              }
            }
          } else {
            const auto* map = std::get_if<EncodableMap>(call.arguments());
            if (map != nullptr) {
              auto found = map->find(EncodableValue(std::string("volume")));
              if (found != map->end()) {
                if (MusicSetVolume set = CoreSymbol<MusicSetVolume>("uae4arm_host_music_set_volume")) {
                  if (const auto* volume = std::get_if<double>(&found->second)) set(static_cast<float>(*volume));
                  else if (const auto* volume = std::get_if<int64_t>(&found->second)) set(static_cast<float>(*volume));
                }
              }
            }
          }
          result->Success(EncodableValue());
        } else if (method == "musicState") {
          EncodableMap state;
          MusicIsBool playing = CoreSymbol<MusicIsBool>("uae4arm_host_music_is_playing");
          MusicIsBool paused = CoreSymbol<MusicIsBool>("uae4arm_host_music_is_paused");
          MusicTitle title = CoreSymbol<MusicTitle>("uae4arm_host_music_title");
          MusicLevel level = CoreSymbol<MusicLevel>("uae4arm_host_music_level");
          state.insert({"playing", EncodableValue(playing != nullptr && playing())});
          state.insert({"paused", EncodableValue(paused != nullptr && paused())});
          state.insert({"title", EncodableValue(std::string(title != nullptr && title() != nullptr ? title() : ""))});
          state.insert({"level", EncodableValue(static_cast<double>(level != nullptr ? level() : 0))});
          result->Success(EncodableValue(state));
        } else {
          result->NotImplemented();
        }
      });

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
