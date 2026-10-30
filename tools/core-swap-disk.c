/* Swaps a disk while the machine is running, the way the in-game disk menu
 * does, and says whether the core took it.
 *
 * A multi-disk game asks for disk two mid-level; the host answers with
 * uae4arm_host_insert_floppy on a thread of its own while the core is
 * inside uae4arm_host_run. The core cannot insert it there and then --
 * the drive has to eject, and the program has to see DSKCHANGE -- so
 * disk_insert only arms it and DISK_vsync finishes the job two emulated
 * seconds later. That handshake is what this exercises: everything between
 * the host call and "Replacement disk ... inserted" in the log.
 *
 *   cc tools/core-swap-disk.c -ldl -lpthread -o core-swap-disk
 *   ./core-swap-disk ./libuae4arm.so <seconds> <drive> <disk.adf> <state.uss> \
 *       [core args...]
 *
 * It prints whether the core accepted the image, and the state it saves
 * afterwards records what each drive really ended up holding.
 */

#include <dlfcn.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*run_fn)(int, char **);
typedef void (*void_fn)(void);
typedef bool (*insert_fn)(int, const char *);
typedef int (*count_fn)(void);
typedef void (*state_fn)(const char *);

static insert_fn core_insert;
static count_fn core_count;
static void_fn core_quit;
static state_fn core_save_state;

static unsigned int swap_after;
static int swap_drive;
static const char *swap_path;
static const char *state_path;

/* The host's side of a swap: wait until the game is up, put the disk in,
   leave it long enough for the eject/insert handshake to finish, quit. */
static void *swap_then_quit(void *unused)
{
    (void)unused;
    sleep(swap_after);
    if (core_count)
        fprintf(stderr, "harness: core reports %d floppy drive(s)\n", core_count());
    fprintf(stderr, "harness: inserting %s into DF%d\n", swap_path, swap_drive);
    /* The core answers whether it could open the image at all. The swap
       itself finishes two emulated seconds later; this is the only moment
       anybody can be told it will not. */
    fprintf(stderr, "harness: insert accepted: %s\n",
            core_insert(swap_drive, swap_path) ? "yes" : "no");
    /* disk_insert arms an eject; DISK_vsync does the insert 2 emulated
       seconds later. Give it more than that before pulling the floor out. */
    sleep(6);
    /* A save state records what is actually in each drive, which is the only
       answer the core will give about a swap it has already finished. */
    if (core_save_state && state_path) {
        fprintf(stderr, "harness: saving state to %s\n", state_path);
        core_save_state(state_path);
        sleep(2);
    }
    fprintf(stderr, "harness: asking the core to quit\n");
    core_quit();
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc < 6) {
        fprintf(stderr,
                "usage: %s <core.so> <seconds> <drive> <disk.adf> <state.uss> "
                "[core arguments...]\n",
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
    core_insert = (insert_fn)dlsym(handle, "uae4arm_host_insert_floppy");
    core_count = (count_fn)dlsym(handle, "uae4arm_host_get_floppy_count");
    core_save_state = (state_fn)dlsym(handle, "uae4arm_host_save_state");
    if (!core_run || !core_quit || !core_insert) {
        fprintf(stderr, "harness: the core does not export what this needs\n");
        return 1;
    }

    swap_after = (unsigned int)strtoul(argv[2], NULL, 10);
    swap_drive = (int)strtol(argv[3], NULL, 10);
    swap_path = argv[4];
    state_path = argv[5];

    int core_argc = argc - 5;
    char **core_argv = calloc((size_t)core_argc + 1, sizeof(char *));
    core_argv[0] = (char *)"Amiga-Retro";
    for (int i = 6; i < argc; i++)
        core_argv[i - 5] = argv[i];

    fprintf(stderr, "harness: ===== run 1 starting =====\n");
    pthread_t swapper;
    pthread_create(&swapper, NULL, swap_then_quit, NULL);
    pthread_detach(swapper);

    int status = core_run(core_argc, core_argv);
    fprintf(stderr, "harness: ===== run 1 returned %d =====\n", status);
    return 0;
}
