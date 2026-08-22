/* Retro-Amiga compliance demo.
 *
 * WRITTEN, NOT SOURCED. The demo has to be a disk the user opens from their
 * own library, and every Amiga program that could serve that purpose is
 * somebody's. This one is ours.
 *
 * It runs from the boot disk's startup-sequence and talks to the ROM through
 * dos.library only -- Write() and Delay(), nothing else -- because that is
 * the part AROS implements most completely. An earlier version of this demo
 * was a boot block poking the copper directly, which is a lovely thing on a
 * real Kickstart and never ran here: it depends on the ROM executing a
 * non-DOS boot block, which is exactly the sort of thing a reimplementation
 * is entitled not to do.
 *
 * Built by tool/build_demo.sh with m68k-amigaos-gcc.
 */
#include <proto/dos.h>
#include <proto/exec.h>

static const char *const LINES[] = {
    "\n",
    "  ========================================\n",
    "     RETRO-AMIGA  --  COMPLIANCE DEMO\n",
    "  ========================================\n",
    "\n",
    "  This is a real emulated Amiga.\n",
    "\n",
    "  It is running on AROS: an open, from-\n",
    "  scratch reimplementation of the Amiga\n",
    "  ROM. No Kickstart of yours is involved,\n",
    "  and none is shipped with this app.\n",
    "\n",
    "  This disk was written for the app. It is\n",
    "  not a commercial program, and no games\n",
    "  are included anywhere in it.\n",
    "\n",
    "  For your own Amiga software you supply\n",
    "  a Kickstart yourself -- see Compliance\n",
    "  in the sidebar.\n",
    "\n",
};

int main(void)
{
    BPTR out = Output();
    ULONG i;

    if (out == 0)
        return 20;

    for (i = 0; i < sizeof(LINES) / sizeof(LINES[0]); i++) {
        const char *line = LINES[i];
        ULONG len = 0;
        while (line[len])
            len++;
        Write(out, (APTR)line, len);
        /* Typed out rather than dumped, so it is visibly a machine doing
         * something rather than a screen that was already there. */
        Delay(8);
    }

    /* Left on screen. The app's own controls are how you leave, the same as
     * for any other disk. */
    for (;;)
        Delay(50);
}
