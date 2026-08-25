#include "sysconfig.h"
#include "sysdeps.h"

#include <atomic>

#include "host_framebuffer.h"
#include "host_texture.h"

namespace {

std::atomic<uae4arm_texture_sink> g_sink{nullptr};
void* g_sink_context = nullptr;

/* The serial of the frame the compositor is already showing. Kept here rather
 * than in the platform sink so every platform gets the same "nothing new, do
 * nothing" behaviour for free. */
std::atomic<uint64_t> g_posted{0};

}  // namespace

void uae4arm_host_texture_set_sink(uae4arm_texture_sink sink, void* context)
{
	g_sink_context = context;
	g_sink.store(sink, std::memory_order_release);
	/* A new sink owns a new surface, and it has nothing on it yet: forget what
	 * the old one was showing so the next present repaints rather than deciding
	 * the frame is already up. This is the Android surface-recreation case --
	 * rotate the device and the compositor hands back a different buffer. */
	g_posted.store(0, std::memory_order_release);
}

bool uae4arm_host_texture_attached(void)
{
	return g_sink.load(std::memory_order_acquire) != nullptr;
}

bool uae4arm_host_texture_present(void)
{
	const uae4arm_texture_sink sink = g_sink.load(std::memory_order_acquire);
	if (sink == nullptr)
		return false;

	const uint64_t available = uae4arm_host_framebuffer_serial();
	if (available == 0 || available == g_posted.load(std::memory_order_acquire))
		return false;

	if (!sink(g_sink_context))
		return false;

	/* Stamp what was asked for, not what arrived. The sink copies whatever is
	 * current at the moment it holds the lock, which may already be newer;
	 * recording the newer number would skip a frame the compositor never saw,
	 * whereas recording this one at worst posts one frame twice. */
	g_posted.store(available, std::memory_order_release);
	return true;
}
