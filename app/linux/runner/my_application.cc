#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <glib.h>
#include <sys/stat.h>
#include <dlfcn.h>

#include <atomic>
#include <string>
#include <thread>
#include <vector>

using HostRun = int (*)(int, char**);
using MusicPlay = bool (*)(const char*);
using MusicStop = void (*)();
using MusicSetPaused = void (*)(bool);
using MusicIsBool = bool (*)();
using MusicTitle = const char* (*)();
using MusicLevel = float (*)();
using MusicSetVolume = void (*)(float);
static void* core_handle = nullptr;

static gchar* app_support_directory();

static HostRun load_core_run() {
  if (core_handle == nullptr) {
    // Flutter installs the runner in the bundle root and native libraries in
    // its lib/ directory. Keep the core as a shared library so the same
    // uae4arm_host API is used by desktop and mobile hosts.
    g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
    g_autofree gchar* directory = executable != nullptr
        ? g_path_get_dirname(executable) : g_strdup(".");
    g_autofree gchar* library =
        g_build_filename(directory, "lib", "libuae4arm.so", nullptr);
    core_handle = dlopen(library, RTLD_NOW | RTLD_GLOBAL);
    if (core_handle == nullptr) {
      g_warning("could not load lib/libuae4arm.so: %s", dlerror());
      return nullptr;
    }
  }
  dlerror();
  HostRun run = reinterpret_cast<HostRun>(dlsym(core_handle, "uae4arm_host_run"));
  const char* error = dlerror();
  if (error != nullptr || run == nullptr) {
    g_warning("core does not export uae4arm_host_run: %s",
              error != nullptr ? error : "unknown error");
    return nullptr;
  }
  return run;
}

template <typename Function>
static Function core_symbol(const char* name) {
  if (load_core_run() == nullptr) return nullptr;
  dlerror();
  Function function = reinterpret_cast<Function>(dlsym(core_handle, name));
  return dlerror() == nullptr ? function : nullptr;
}

// The channel the launcher talks to. On Android and iOS the other end starts
// the emulator and answers where things live; on the desktop there is no host
// app around the launcher, so this answers for itself.
static constexpr char kChannel[] = "uae4arm2026/emulator";

// Everything the launcher writes lives under one directory, the way it does on
// a phone: configs, save states, the media index and the pad layout.
static gchar* app_support_directory() {
  g_autofree gchar* path =
      g_build_filename(g_get_user_data_dir(), "uae4arm2026", nullptr);
  // Made on demand, because the launcher expects to be handed somewhere it can
  // write rather than somewhere it has to create.
  g_mkdir_with_parents(path, 0755);
  return g_steal_pointer(&path);
}

static void handle_method_call(FlMethodChannel* channel, FlMethodCall* call,
                               gpointer user_data) {
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "platformName") == 0) {
    g_autoptr(FlValue) value = fl_value_new_string("linux");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "appSupportDirectory") == 0 ||
             g_strcmp0(method, "emulatorHomeDirectory") == 0) {
    g_autofree gchar* path = app_support_directory();
    g_autoptr(FlValue) value = fl_value_new_string(path);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "documentsDirectory") == 0) {
    // Where a person keeps their disks, not where the app keeps its state:
    // on a desktop those are different places, and the scan starts here.
    const gchar* documents = g_get_user_special_dir(G_USER_DIRECTORY_DOCUMENTS);
    g_autoptr(FlValue) value =
        fl_value_new_string(documents != nullptr ? documents : g_get_home_dir());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "appBuildStamp") == 0) {
    // The executable's timestamp: a rebuild rewrites it, which is a deploy on
    // a desktop.
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    struct stat info;
    const gchar* target = exe != nullptr ? exe : "/proc/self/exe";
    const gint64 stamp = stat(target, &info) == 0 ? (gint64)info.st_mtime : 0;
    g_autofree gchar* text = g_strdup_printf("%" G_GINT64_FORMAT, stamp);
    g_autoptr(FlValue) value = fl_value_new_string(text);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "hasAllFilesAccess") == 0) {
    // A desktop has no scoped storage to ask permission of; the launcher can
    // read what the user can read.
    g_autoptr(FlValue) value = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "requestAllFilesAccess") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "openControllerMapping") == 0) {
    // There is no controller mapping UI in this desktop shell.
    g_autoptr(FlValue) value = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (g_strcmp0(method, "musicPlay") == 0) {
    FlValue* arguments = fl_method_call_get_args(call);
    FlValue* path = arguments != nullptr &&
            fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(arguments, "path") : nullptr;
    MusicPlay play = core_symbol<MusicPlay>("uae4arm_host_music_play");
    const bool ok = play != nullptr && path != nullptr &&
        fl_value_get_type(path) == FL_VALUE_TYPE_STRING &&
        play(fl_value_get_string(path));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(ok)));
  } else if (g_strcmp0(method, "musicStop") == 0 ||
             g_strcmp0(method, "musicReleaseAudio") == 0 ||
             g_strcmp0(method, "musicSetPaused") == 0 ||
             g_strcmp0(method, "musicSetVolume") == 0) {
    if (g_strcmp0(method, "musicStop") == 0) {
      if (MusicStop stop = core_symbol<MusicStop>("uae4arm_host_music_stop")) stop();
    } else if (g_strcmp0(method, "musicReleaseAudio") == 0) {
      if (MusicStop release = core_symbol<MusicStop>("uae4arm_host_music_release_audio"))
        release();
    } else if (g_strcmp0(method, "musicSetPaused") == 0) {
      FlValue* arguments = fl_method_call_get_args(call);
      FlValue* paused = arguments != nullptr &&
              fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(arguments, "paused") : nullptr;
      if (MusicSetPaused set = core_symbol<MusicSetPaused>("uae4arm_host_music_set_paused"))
        set(paused != nullptr && fl_value_get_type(paused) == FL_VALUE_TYPE_BOOL &&
            fl_value_get_bool(paused));
    } else if (MusicSetVolume set = core_symbol<MusicSetVolume>("uae4arm_host_music_set_volume")) {
      FlValue* arguments = fl_method_call_get_args(call);
      FlValue* volume = arguments != nullptr &&
              fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(arguments, "volume") : nullptr;
      if (volume != nullptr && fl_value_get_type(volume) == FL_VALUE_TYPE_FLOAT)
        set(static_cast<float>(fl_value_get_float(volume)));
      else if (volume != nullptr && fl_value_get_type(volume) == FL_VALUE_TYPE_INT)
        set(static_cast<float>(fl_value_get_int(volume)));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else if (g_strcmp0(method, "musicState") == 0) {
    g_autoptr(FlValue) state = fl_value_new_map();
    MusicIsBool playing = core_symbol<MusicIsBool>("uae4arm_host_music_is_playing");
    MusicIsBool paused = core_symbol<MusicIsBool>("uae4arm_host_music_is_paused");
    MusicTitle title = core_symbol<MusicTitle>("uae4arm_host_music_title");
    MusicLevel level = core_symbol<MusicLevel>("uae4arm_host_music_level");
    fl_value_set_string_take(state, "playing", fl_value_new_bool(playing != nullptr && playing()));
    fl_value_set_string_take(state, "paused", fl_value_new_bool(paused != nullptr && paused()));
    fl_value_set_string_take(state, "title", fl_value_new_string(title != nullptr && title() != nullptr ? title() : ""));
    fl_value_set_string_take(state, "level", fl_value_new_float(level != nullptr ? level() : 0));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(state));
  } else if (g_strcmp0(method, "launch") == 0) {
    // There is no native game window any more: the machine renders inside
    // the Flutter panel via the in-process FFI core, the same surface every
    // platform uses. Dart only falls back to this channel when that core
    // failed to load -- and this runner loads the same libuae4arm.so, so
    // there is nothing truthful to do here but say so.
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "launch_failed",
        "The emulator core could not be loaded (lib/libuae4arm.so).",
        nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("failed to answer %s: %s", method, error->message);
  }
}

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "uae4arm2026");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "uae4arm2026");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannel,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_method_call,
                                            g_object_ref(view), g_object_unref);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
