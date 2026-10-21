// smoke.c - prove the bridge boots a machine and renders frames.
//   cc smoke.c -L target/release -lcopperline_ffi -o smoke && LD_LIBRARY_PATH=target/release ./smoke <rom> [ext]
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ClEmu ClEmu;
extern ClEmu *cl_new(const char *model, const char *video, int floppy_drives);
extern void cl_free(ClEmu *);
extern size_t cl_version(char *out, size_t cap);
extern int cl_load_rom(ClEmu *, const unsigned char *rom, size_t, const unsigned char *ext, size_t);
extern int cl_run(ClEmu *, double now_ms, unsigned max_frames);
extern const unsigned *cl_present_ptr(ClEmu *);
extern unsigned cl_present_width(ClEmu *);
extern unsigned cl_present_rows(ClEmu *);
extern size_t cl_take_audio(ClEmu *, float *out, size_t cap);

static unsigned char *slurp(const char *path, size_t *len) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END); *len = ftell(f); fseek(f, 0, SEEK_SET);
  unsigned char *buf = malloc(*len);
  fread(buf, 1, *len, f); fclose(f);
  return buf;
}

int main(int argc, char **argv) {
  char v[64]; cl_version(v, sizeof v);
  printf("version: %s\n", v);

  ClEmu *e = cl_new("A1200", "PAL", 1);
  if (!e) { printf("cl_new FAILED\n"); return 1; }
  printf("machine: A1200 PAL, 1 drive\n");

  if (argc > 1) {
    size_t rl = 0, xl = 0;
    unsigned char *rom = slurp(argv[1], &rl);
    unsigned char *ext = argc > 2 ? slurp(argv[2], &xl) : NULL;
    if (!rom) { printf("rom unreadable\n"); return 1; }
    if (cl_load_rom(e, rom, rl, ext, xl) != 0) { printf("load_rom FAILED\n"); return 1; }
    printf("rom loaded: %zu bytes\n", rl);
  }

  double now = 0;
  int total = 0;
  float audio[8192];
  size_t audio_total = 0;
  for (int tick = 0; tick < 100; tick++) {
    now += 20.0; // 50 ticks/s wall clock
    int n = cl_run(e, now, 4);
    if (n < 0) { printf("run FAILED at tick %d\n", tick); return 1; }
    total += n;
    audio_total += cl_take_audio(e, audio, 8192);
  }
  unsigned w = cl_present_width(e), r = cl_present_rows(e);
  printf("frames stepped: %d, present: %ux%u, audio samples: %zu\n", total, w, r, audio_total);

  // Any non-black pixel proves the render path carried picture out.
  const unsigned *px = cl_present_ptr(e);
  size_t lit = 0;
  for (size_t i = 0; i < (size_t)w * r; i++) if ((px[i] & 0xFFFFFF00) != 0 && (px[i] >> 8) != 0) lit++;
  printf("non-black pixels: %zu / %u\n", lit, w * r);

  cl_free(e);
  printf(total >= 90 && r > 0 ? "SMOKE PASS\n" : "SMOKE WEAK (check numbers)\n");
  return 0;
}
