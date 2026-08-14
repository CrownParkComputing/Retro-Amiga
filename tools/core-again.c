/* Runs the emulator core twice in one process with DIFFERENT arguments,
 * the way a phone host does when the player leaves one game and starts
 * another. core-twice.c covers the same-game case; this covers the one it
 * missed - a freeze that only happened with a new config and a new archive
 * on the second run.
 *
 *   cc tools/core-again.c -ldl -lpthread -o core-again
 *   ./core-again ./libuae4arm.so <run1 args...> -- <run2 args...>
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

static void *quit_after_delay(void *seconds)
{
    sleep((unsigned int)(long)seconds);
    if (core_quit) {
        fprintf(stderr, "harness: asking the core to quit\n");
        core_quit();
    }
    return NULL;
}

static int run_once(run_fn core_run, int argc, char **argv, int pass)
{
    fprintf(stderr, "\nharness: ===== run %d starting =====\n", pass);
    pthread_t quitter;
    pthread_create(&quitter, NULL, quit_after_delay, (void *)(long)8);
    pthread_detach(quitter);
    int status = core_run(argc, argv);
    fprintf(stderr, "harness: ===== run %d returned %d =====\n", pass, status);
    return status;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr,
                "usage: %s <core.so> <run1 args...> -- <run2 args...>\n",
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
        fprintf(stderr, "harness: missing exports\n");
        return 1;
    }

    /* Split what follows the library path at "--". */
    int split = argc;
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) {
            split = i;
            break;
        }
    }

    char *first[64], *second[64];
    int n1 = 0, n2 = 0;
    first[n1++] = (char *)"Amiga-Retro";
    for (int i = 2; i < split && n1 < 63; i++)
        first[n1++] = argv[i];
    first[n1] = NULL;
    second[n2++] = (char *)"Amiga-Retro";
    for (int i = split + 1; i < argc && n2 < 63; i++)
        second[n2++] = argv[i];
    second[n2] = NULL;

    run_once(core_run, n1, first, 1);
    run_once(core_run, n2, second, 2);
    fprintf(stderr, "harness: both runs completed\n");
    return 0;
}
