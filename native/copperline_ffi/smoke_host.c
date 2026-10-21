// smoke_host.c - prove the uae4arm_host_* surface runs a machine, publishes
// frames, takes a quit, and can be run a second time in one process (the
// run-quit-run lifecycle the phone hosts exercise).
//
//   cc smoke_host.c -L target/release -lcopperline_ffi -lpthread -o smoke_host
//   LD_LIBRARY_PATH=target/release ./smoke_host [config.toml]
//
// With no argument it writes a minimal A1200 TOML to /tmp and runs that;
// the bundled AROS ROM means no Kickstart is needed.
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int uae4arm_host_run(int argc, char **argv);
extern void uae4arm_host_quit(void);
extern void uae4arm_host_set_pause(int paused);
extern void uae4arm_host_set_framebuffer_output(int enabled);
extern unsigned long long uae4arm_host_framebuffer_serial(void);
extern void uae4arm_host_framebuffer_size(int *w, int *h);
extern int uae4arm_host_copy_framebuffer(unsigned *dst, int cap, int *w, int *h,
                                         unsigned long long *serial);
extern void uae4arm_host_insert_floppy(int drive, const char *path);
extern int uae4arm_host_get_floppy_count(void);
extern int uae4arm_host_pad_port(void);
extern void uae4arm_host_swap_pad_port(void);
extern void uae4arm_host_pad_attach(int pad);
extern void uae4arm_host_pad_direction(int pad, int l, int r, int u, int d);
extern void uae4arm_host_pad_button(int pad, int button, int pressed);
extern void uae4arm_host_mouse_move(int dx, int dy);
extern void uae4arm_host_send_key(int key, int pressed);
extern int uae4arm_host_save_session(void);
extern void uae4arm_host_set_session(const char *s, const char *c, const char *t);

static char *g_argv[8];
static int g_argc;
static int g_result = -999;

static void *runner(void *unused) {
  (void)unused;
  g_result = uae4arm_host_run(g_argc, g_argv);
  return NULL;
}

static int wait_serial(unsigned long long want, int seconds) {
  for (int i = 0; i < seconds * 100; i++) {
    if (uae4arm_host_framebuffer_serial() >= want) return 1;
    usleep(10000);
  }
  return 0;
}

static int run_once(const char *config, const char *state, int n) {
  printf("--- run %d: config=%s\n", n, config ? config : "(none)");
  g_argc = 0;
  g_argv[g_argc++] = "smoke_host";
  if (config) {
    g_argv[g_argc++] = "--config";
    g_argv[g_argc++] = (char *)config;
  }
  if (state) {
    g_argv[g_argc++] = "--statefile";
    g_argv[g_argc++] = (char *)state;
  }
  uae4arm_host_set_framebuffer_output(1);

  pthread_t th;
  pthread_create(&th, NULL, runner, NULL);

  // ~8s of emulated time: AROS spends several seconds on a black screen
  // before the workbench comes up, so judging the picture earlier reports
  // "black" for a machine that is in fact booting fine.
  if (!wait_serial(400, 45)) {
    printf("run %d: no published frames within 30s\n", n);
    uae4arm_host_quit();
    pthread_join(th, NULL);
    return 0;
  }

  int w = 0, h = 0;
  uae4arm_host_framebuffer_size(&w, &h);
  unsigned long long serial = 0;
  unsigned *buf = malloc((size_t)w * h * 4);
  int copied = uae4arm_host_copy_framebuffer(buf, w * h, &w, &h, &serial);
  size_t lit = 0;
  for (int i = 0; i < copied; i++)
    if ((buf[i] & 0xFFFFFF) != 0) lit++;
  printf("run %d: frame %dx%d serial=%llu copied=%d lit=%zu/%d\n", n, w, h,
         serial, copied, lit, copied);
  free(buf);

  // Exercise the control surface: input, pad swap, pause, session save.
  uae4arm_host_pad_attach(1);
  uae4arm_host_pad_direction(1, 0, 0, 1, 0);
  uae4arm_host_pad_button(1, 0, 1);
  uae4arm_host_pad_button(1, 0, 0);
  uae4arm_host_mouse_move(12, -8);
  uae4arm_host_send_key(0x20, 1); // 'a' rawkey down+up
  uae4arm_host_send_key(0x20, 0);
  uae4arm_host_swap_pad_port();
  usleep(100000);
  printf("run %d: pad now in port %d, floppies=%d\n", n, uae4arm_host_pad_port(),
         uae4arm_host_get_floppy_count());
  uae4arm_host_swap_pad_port();

  if (config) {
    char sp[512], tp[128];
    snprintf(sp, sizeof sp, "/tmp/cl-smoke/states/run%d.clstate", n);
    snprintf(tp, sizeof tp, "smoke %d", n);
    uae4arm_host_set_session(sp, config, tp);
    if (!uae4arm_host_save_session()) printf("run %d: save_session refused\n", n);
    usleep(300000); // let the drain write it
  }

  uae4arm_host_set_pause(1);
  usleep(100000);
  uae4arm_host_set_pause(0);
  usleep(200000);

  uae4arm_host_quit();
  pthread_join(th, NULL);
  printf("run %d: exited with %d\n", n, g_result);
  return g_result == 0 && copied > 0 && lit > 0;
}

int main(int argc, char **argv) {
  const char *config = argc > 1 ? argv[1] : "/tmp/cl-smoke/smoke.toml";
  if (argc <= 1) {
    system("mkdir -p /tmp/cl-smoke/states");
    FILE *f = fopen(config, "w");
    fputs("[machine]\nmodel = \"a1200\"\n", f);
    fclose(f);
  }
  int ok = run_once(config, NULL, 1);
  // Second run re-enters the library in the same process.
  char state[512];
  snprintf(state, sizeof state, "/tmp/cl-smoke/states/run1.clstate");
  int ok2 = run_once(config, access(state, R_OK) == 0 ? state : NULL, 2);
  printf("%s\n", ok && ok2 ? "HOST SMOKE OK" : "HOST SMOKE FAILED");
  return ok && ok2 ? 0 : 1;
}
