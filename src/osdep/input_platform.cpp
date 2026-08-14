#include "sysdeps.h"
#include "input_platform.h"

#include <SDL3/SDL.h>

#include <string>

#include "amiberry_input.h"
#include "fsdb.h"
#include "target.h"

void osdep_init_keyboard(int* keyboard_german, int* retroarch_inited, int* num_retroarch_kbdjoy)
{
	if (!keyboard_german || !retroarch_inited || !num_retroarch_kbdjoy)
		return;

	/* Once per process. The layout does not change mid-session, and on iOS
	   this SDL call consults the keymap of a keyboard whose window went away
	   with the previous run - the second run's init_kb froze right here,
	   which surfaced as "loading an ADF after a WHDLoad game hangs". */
	static int cached_german = -1;
	if (cached_german < 0) {
		cached_german =
			SDL_GetKeyFromScancode(SDL_SCANCODE_Y, SDL_KMOD_NONE, false) == SDLK_Z
				? 1 : 0;
	}
	*keyboard_german = cached_german;

	if (*retroarch_inited)
		return;

	std::string retroarch_file = get_retroarch_file();
	if (my_existsfile2(retroarch_file.c_str()))
	{
		bool valid = true;
		for (int kb = 0; kb < 4 && valid; ++kb)
		{
			valid = init_kb_from_retroarch(kb, retroarch_file);
			if (valid)
				(*num_retroarch_kbdjoy)++;
		}
	}
	*retroarch_inited = 1;
}
