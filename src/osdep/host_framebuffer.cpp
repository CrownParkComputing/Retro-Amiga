#include "sysconfig.h"
#include "sysdeps.h"

#include <SDL3/SDL.h>

#include <atomic>
#include <cstring>
#include <mutex>
#include <vector>

#include "options.h"
#include "host_framebuffer.h"

unsigned long host_getline_unlocked = 0;
unsigned long host_getline_locked = 0;
unsigned long host_getline_none = 0;
unsigned long host_getline_row = 0;

namespace {

/*
 * Two buffers, not one.
 *
 * The emulation thread writes a frame while the UI thread may still be reading
 * the previous one. Writing into the buffer being read is how a tearing bug
 * that only shows on slow frames gets built in; swapping costs one pointer.
 */
struct FrameBuffer {
	std::vector<uint32_t> pixels;
	int width = 0;
	int height = 0;
};

FrameBuffer g_frames[2];
std::atomic<int> g_front{0};
std::atomic<uint64_t> g_serial{0};
std::atomic<bool> g_enabled{false};

/* Guards the swap only -- the copy itself happens into the back buffer, which
 * no reader can be holding. */
std::mutex g_swap_mutex;

}  // namespace

void uae4arm_host_set_framebuffer_output(bool enabled)
{
	g_enabled.store(enabled, std::memory_order_release);
	if (!enabled)
		return;
	{
		std::lock_guard<std::mutex> lock(g_swap_mutex);
		for (FrameBuffer& frame : g_frames) {
			frame.pixels.clear();
			frame.width = 0;
			frame.height = 0;
		}
		g_front.store(0, std::memory_order_release);
		g_serial.store(0, std::memory_order_release);
	}

	/*
	 * Pick the offscreen video driver, here rather than in the caller.
	 *
	 * Setting SDL_VIDEODRIVER in the environment from the app did not take:
	 * the log still said "SDL video driver: android", and the Android driver
	 * then asks SDLActivity for a window that does not exist in the
	 * launcher's process, so the core never gets past creating one. A hint
	 * set before SDL_Init is read by SDL itself and cannot be missed the way
	 * an environment variable set on the wrong side of a process boundary
	 * can.
	 *
	 * This is the right place for it: framebuffer output IS the windowless
	 * mode, so the driver that needs no window belongs with it.
	 */
	SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "offscreen");

	/*
	 * Headless has to be set HERE, in both prefs, before the core runs.
	 *
	 * `-s headless=yes` on the command line was not enough, and the log said
	 * why in a way that took a while to read: main.cpp calls graphics_setup()
	 * BEFORE parse_cmdline_and_init_file(). So the initial surface and
	 * renderer were built windowed (headless still false from defaults), and
	 * only afterwards did the flag flip -- at which point show_screen()
	 * started early-returning on a surface the renderer path owned, and
	 * nothing published. The 752x576 surface that "never had pixels" was the
	 * windowed doInit's recreation of it; the 1920x1080 one seen earlier was
	 * the real headless surface, created and then abandoned.
	 *
	 * Setting currprefs AND changed_prefs means graphics_setup() sees it, and
	 * the first reset's copy_prefs(&changed_prefs, &currprefs) does not undo
	 * it.
	 */
	currprefs.headless = true;
	changed_prefs.headless = true;
	write_log("host framebuffer output on; headless + offscreen video driver\n");
}

bool uae4arm_host_framebuffer_output(void)
{
	return g_enabled.load(std::memory_order_acquire);
}

uint64_t uae4arm_host_framebuffer_serial(void)
{
	return g_serial.load(std::memory_order_acquire);
}

void uae4arm_host_publish_frame(const SDL_Surface* surface)
{
	uae4arm_host_publish_frame_region(surface, 0, 0);
}

void uae4arm_host_publish_frame_region(const SDL_Surface* surface,
                                       int used_width, int used_height)
{
	if (surface == nullptr || surface->w <= 0 || surface->h <= 0)
		return;
	const int sw = (used_width > 0 && used_width <= surface->w)
		? used_width : surface->w;
	const int sh = (used_height > 0 && used_height <= surface->h)
		? used_height : surface->h;
	uae4arm_host_publish_frame_pixels(surface->pixels, sw, sh, surface->pitch);
}

void uae4arm_host_publish_frame_pixels(const void* pixels_in, int width,
                                       int height, int pitch)
{
	if (pixels_in == nullptr || width <= 0 || height <= 0 || pitch <= 0)
		return;

	const int back = 1 - g_front.load(std::memory_order_acquire);
	FrameBuffer& fb = g_frames[back];

	const int w = width;
	const int h = height;
	const size_t count = static_cast<size_t>(w) * static_cast<size_t>(h);
	if (fb.pixels.size() != count)
		fb.pixels.resize(count);
	fb.width = w;
	fb.height = h;

	/*
	 * Row by row, and nothing else.
	 *
	 * Row by row because the surface is padded to its pitch, and a straight
	 * memcpy of w*h*4 would walk into the padding and shear the picture.
	 *
	 * This used to force the alpha byte opaque as it went, pixel by pixel.
	 * The format is ABGR8888 and the emulator leaves the top byte zero, so a
	 * compositor that respects alpha draws a perfectly correct picture
	 * entirely transparent -- which looks exactly like the core drawing
	 * nothing, and cost a long evening the first time.
	 *
	 * But it is the wrong place to fix it. This runs for every published
	 * frame, and at the 1920x1080 an RTG collection asks for that is two
	 * million read-modify-writes fifty times a second, on the thread whose
	 * scheduling latency is what audio underruns are made of. The two
	 * consumers can each deal with alpha far more cheaply: the compositor is
	 * handed an RGBX window, where the byte is ignored by definition, and the
	 * Dart fallback -- which is rare, and already copying -- ORs it in as it
	 * copies. See uae4arm_host_copy_framebuffer.
	 */
	const uint8_t* src = static_cast<const uint8_t*>(pixels_in);
	uint32_t* dst = fb.pixels.data();
	const size_t row_bytes = static_cast<size_t>(w) * sizeof(uint32_t);
	for (int y = 0; y < h; y++) {
		std::memcpy(dst + static_cast<size_t>(y) * w,
			src + static_cast<size_t>(y) * pitch, row_bytes);
	}

	{
		std::lock_guard<std::mutex> lock(g_swap_mutex);
		g_front.store(back, std::memory_order_release);
	}
	const uint64_t serial = g_serial.fetch_add(1, std::memory_order_acq_rel) + 1;
	/* The first frame is the one worth knowing about: it is the difference
	 * between "the core is wedged" and "the UI is not drawing". */
	if (serial == 1)
		write_log("host framebuffer: first frame published (%dx%d)\n", w, h);

	/*
	 * Is there a picture in here at all?
	 *
	 * A published frame of the right size, in the right format, containing
	 * nothing has now cost several rebuilds of theorising. Counting the
	 * non-black pixels answers in one line whether the emulator is producing
	 * an image that this code is losing, or not producing one at all -- and
	 * how many times the emulation locked a buffer to draw says which end to
	 * look at.
	 */
	/* Counted on every change of shape as well as at fixed serials.
	 *
	 * A screen-mode switch is exactly when a frame goes black, and reporting
	 * only at frames 1, 100 and 300 means the one frame worth counting is
	 * never the one counted. */
	static int counted_w = 0, counted_h = 0;
	const bool shape_changed = (w != counted_w || h != counted_h);
	if (shape_changed) {
		counted_w = w;
		counted_h = h;
	}
	if (serial == 1 || serial == 100 || serial == 300 || shape_changed) {
		extern unsigned long host_lockscr_calls, host_lockscr_ok,
			host_lockscr_nowindow, host_lockscr_nosurface;
		size_t lit = 0;
		for (size_t i = 0; i < fb.pixels.size(); i++) {
			if ((fb.pixels[i] & 0x00FFFFFFu) != 0) lit++;
		}
		write_log("host framebuffer: frame %llu has %zu/%zu non-black pixels "
			"(lockscr calls %lu ok %lu nowindow %lu nosurface %lu; get_line "
			"unlocked %lu locked %lu none %lu row %lu)\n",
			(unsigned long long)serial, lit, fb.pixels.size(),
			host_lockscr_calls, host_lockscr_ok, host_lockscr_nowindow,
			host_lockscr_nosurface, host_getline_unlocked,
			host_getline_locked, host_getline_none, host_getline_row);
	}
}

int uae4arm_host_copy_framebuffer(uint32_t* dst, int dst_capacity,
                                  int* out_width, int* out_height,
                                  uint64_t* out_serial)
{
	std::lock_guard<std::mutex> lock(g_swap_mutex);
	const FrameBuffer& fb = g_frames[g_front.load(std::memory_order_acquire)];
	if (out_serial)
		*out_serial = g_serial.load(std::memory_order_acquire);
	if (out_width)
		*out_width = fb.width;
	if (out_height)
		*out_height = fb.height;
	if (fb.pixels.empty() || dst == nullptr)
		return 0;
	const int count = fb.width * fb.height;
	if (count <= 0 || count > dst_capacity)
		return 0;
	/*
	 * Alpha forced opaque HERE, not in the publisher.
	 *
	 * This is the fallback path -- decodeImageFromPixels, which reads the
	 * frame as rgba8888 and would draw a fully transparent picture over the
	 * panel's own background. It already costs a copy and a decode per frame
	 * and is only reached where the external texture could not be used, so a
	 * pass over the pixels here is affordable in a way the same pass on every
	 * published frame is not.
	 */
	const uint32_t* src = fb.pixels.data();
	for (int i = 0; i < count; i++)
		dst[i] = src[i] | 0xFF000000u;
	return count;
}

void uae4arm_host_framebuffer_size(int* out_width, int* out_height)
{
	std::lock_guard<std::mutex> lock(g_swap_mutex);
	const FrameBuffer& fb = g_frames[g_front.load(std::memory_order_acquire)];
	if (out_width)
		*out_width = fb.pixels.empty() ? 0 : fb.width;
	if (out_height)
		*out_height = fb.pixels.empty() ? 0 : fb.height;
}

int uae4arm_host_copy_framebuffer_strided(uint32_t* dst, int dst_stride,
                                          int dst_rows, int* out_width,
                                          int* out_height,
                                          uint64_t* out_serial)
{
	std::lock_guard<std::mutex> lock(g_swap_mutex);
	const FrameBuffer& fb = g_frames[g_front.load(std::memory_order_acquire)];
	if (out_serial)
		*out_serial = g_serial.load(std::memory_order_acquire);
	if (out_width)
		*out_width = fb.width;
	if (out_height)
		*out_height = fb.height;
	if (fb.pixels.empty() || dst == nullptr)
		return 0;
	if (fb.width <= 0 || fb.height <= 0)
		return 0;
	/* Refuse rather than shear: a destination too narrow or too short for the
	 * mode the Amiga just switched to is the caller's cue to resize it. */
	if (fb.width > dst_stride || fb.height > dst_rows)
		return 0;

	const uint32_t* src = fb.pixels.data();
	if (dst_stride == fb.width) {
		std::memcpy(dst, src,
			static_cast<size_t>(fb.width) * static_cast<size_t>(fb.height) *
			sizeof(uint32_t));
	} else {
		for (int y = 0; y < fb.height; y++) {
			std::memcpy(dst + static_cast<size_t>(y) * dst_stride,
				src + static_cast<size_t>(y) * fb.width,
				static_cast<size_t>(fb.width) * sizeof(uint32_t));
		}
	}
	return fb.width * fb.height;
}

const uint32_t* uae4arm_host_get_framebuffer(int* out_width, int* out_height,
                                             uint64_t* out_serial)
{
	std::lock_guard<std::mutex> lock(g_swap_mutex);
	const FrameBuffer& fb = g_frames[g_front.load(std::memory_order_acquire)];
	if (out_serial)
		*out_serial = g_serial.load(std::memory_order_acquire);
	if (fb.pixels.empty())
		return nullptr;
	if (out_width)
		*out_width = fb.width;
	if (out_height)
		*out_height = fb.height;
	return fb.pixels.data();
}
