/* Runs the emulator core twice in one process, the way a phone host does.
 *
 * On iOS the launcher and the emulator share a process: the core is entered
 * through uae4arm_host_run and, when a game is left, it returns. Starting a
 * second game runs it again - and that second run never comes back, which
 * takes the whole app with it because the core is on the main thread.
 *
 * That is not reproducible from the emulator's own binary, which runs the core
 * once and exits, so this harness stands in for the host: dlopen the core, run
 * it, quit it from another thread, and run it again. Same code, on a desktop,
 * where a debugger can be attached.
 *
 *   cc tools/core-twice.c -ldl -lpthread -o core-twice
 *   ./core-twice ./libuae4arm.so [extra core arguments...]
 *
 * It prints where each run gets to. If the second run hangs, attach gdb to
 * this process and the backtrace is the answer.
 */

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*run_fn)(int, char **);
typedef void (*void_fn)(void);

static void_fn core_quit;

/* Ends the run a few seconds in, which is what pressing the exit button does
   on the device. */
static void *quit_after_delay(void *seconds)
{
    sleep((unsigned int)(long)seconds);
    if (core_quit) {
        fprintf(stderr, "harness: asking the core to quit\n");
        core_quit();
    }
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <path to libuae4arm.so> [core arguments...]\n",
                argv[0]);
        return 2;
    }

    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "harness: could not load the core: %s\n", dlerror());
        return 1;
    }

    run_fn core_run = (run_fn)dlsym(handle, "uae4arm_host_run");
    core_quit = (void_fn)dlsym(handle, "uae4arm_host_quit");
    if (!core_run || !core_quit) {
        fprintf(stderr, "harness: the core does not export what this needs\n");
        return 1;
    }

    /* argv[0] is the program name, as the core's option parser expects; the
       rest is whatever was passed after the library path. */
    int core_argc = argc - 1;
    char **core_argv = calloc((size_t)core_argc + 1, sizeof(char *));
    core_argv[0] = (char *)"Amiga-Retro";
    for (int i = 2; i < argc; i++)
        core_argv[i - 1] = argv[i];

    for (int pass = 1; pass <= 2; pass++) {
        fprintf(stderr, "\nharness: ===== run %d starting =====\n", pass);

        pthread_t quitter;
        pthread_create(&quitter, NULL, quit_after_delay, (void *)(long)8);
        pthread_detach(quitter);

        int status = core_run(core_argc, core_argv);
        fprintf(stderr, "harness: ===== run %d returned %d =====\n", pass, status);
    }

    fprintf(stderr, "harness: both runs completed\n");
    return 0;
}
