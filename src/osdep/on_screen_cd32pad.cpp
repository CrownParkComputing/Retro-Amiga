/*
 * Amiberry - On-screen CD32 gamepad overlay
 *
 * Provides a virtual CD32 controller overlay for touchscreen devices.
 * Layout: D-pad (left), 4 colored face buttons in diamond (right),
 * 3 media buttons (Play/RWD/FFW) in a row below the face buttons.
 *
 * Registered as a proper joystick input device so it appears in the Input
 * configuration panel and respects the selected port mode (CD32 pad).
 *
 * Supports both SDL software renderer and OpenGL rendering paths.
 *
 * Copyright 2025-2026 Amiberry team
 */

#include <cmath>
#include <cstring>
#include <vector>
#include <algorithm>

#include <SDL3/SDL.h>

#ifdef USE_OPENGL
#include "on_screen_joystick_gl.h"
#endif

// SDL3 helper: convert SDL_Rect to SDL_FRect for SDL_RenderTexture
static inline SDL_FRect rect_to_frect(const SDL_Rect* r)
{
	if (!r) return SDL_FRect{0, 0, 0, 0};
	return SDL_FRect{ static_cast<float>(r->x), static_cast<float>(r->y),
		static_cast<float>(r->w), static_cast<float>(r->h) };
}

#include "on_screen_cd32pad.h"
#include "sysdeps.h"
#include "inputdevice.h"
#include "amiberry_input.h"
#include "options.h"
#include "amiberry_gfx.h"
#include "irenderer.h"

// ---------------------------------------------------------------------------
// Configuration constants
// ---------------------------------------------------------------------------

// D-pad base size as fraction of shorter screen dimension
static constexpr float DPAD_SIZE_FRACTION = 0.34f;
// Face button size as fraction of shorter dimension
static constexpr float FACE_BTN_SIZE_FRACTION = 0.15f;
// Media button size (smaller than face buttons)
static constexpr float MEDIA_BTN_SIZE_FRACTION = 0.10f;
// Margin from screen edge
static constexpr float EDGE_MARGIN_FRACTION = 0.02f;
// Spacing between face buttons in diamond
static constexpr float DIAMOND_SPACING_FRACTION = 0.02f;
// Gap between face button diamond and media button row
static constexpr float MEDIA_GAP_FRACTION = 0.03f;
// Gap between media buttons in the row
static constexpr float MEDIA_BTN_GAP_FRACTION = 0.01f;

// Texture resolution
static constexpr int STICK_BASE_TEX_SIZE = 256;
static constexpr int STICK_KNOB_TEX_SIZE = 128;
static constexpr int BUTTON_TEX_SIZE = 128;
static constexpr int SHOULDER_TEX_W = 192;
static constexpr int SHOULDER_TEX_H = 96;

// Alpha values (0-255)
static constexpr uint8_t ALPHA_NORMAL = 160;
static constexpr uint8_t ALPHA_PRESSED = 220;

// D-pad parameters
static constexpr float DPAD_DEADZONE = 0.15f;
static constexpr float DPAD_RELEASE_RADIUS = 2.5f;
static constexpr float KNOB_SIZE_FRACTION = 0.40f;
static constexpr float KNOB_MAX_TRAVEL = 0.55f;

// ---------------------------------------------------------------------------
// Color palette — CD32 pad colors
// ---------------------------------------------------------------------------

struct Color {
	uint8_t r, g, b, a;
};

// D-pad base plate
static constexpr Color STICK_BASE_OUTER    = { 25,  25,  30, 255 };
static constexpr Color STICK_BASE_BEVEL    = { 50,  50,  56, 255 };
static constexpr Color STICK_BASE_WELL_IN  = { 30,  30,  35, 255 };
static constexpr Color STICK_BASE_WELL_OUT = { 45,  45,  52, 255 };
static constexpr Color STICK_DIR_DOT       = { 70,  70,  78, 180 };
static constexpr Color STICK_CENTER_DOT    = { 55,  55,  62, 255 };

// Knob
static constexpr Color KNOB_OUTER    = {140,  15,  15, 255 };
static constexpr Color KNOB_INNER    = {230,  55,  55, 255 };
static constexpr Color KNOB_GLINT    = {255, 180, 180, 255 };

// CD32 face buttons — matching real controller colors
// Red button (fire 1)
static constexpr Color BTN_RED_OUTER     = {160,  20,  20, 255 };
static constexpr Color BTN_RED_INNER     = {220,  50,  50, 255 };
static constexpr Color BTN_RED_HIGHLIGHT = {255, 100, 100, 255 };

// Blue button (fire 2)
static constexpr Color BTN_BLUE_OUTER     = { 20,  40, 160, 255 };
static constexpr Color BTN_BLUE_INNER     = { 50,  70, 220, 255 };
static constexpr Color BTN_BLUE_HIGHLIGHT = {100, 130, 255, 255 };

// Green button
static constexpr Color BTN_GREEN_OUTER     = { 20, 130,  40, 255 };
static constexpr Color BTN_GREEN_INNER     = { 50, 180,  70, 255 };
static constexpr Color BTN_GREEN_HIGHLIGHT = {100, 230, 130, 255 };

// Yellow button
static constexpr Color BTN_YELLOW_OUTER     = {160, 140,  20, 255 };
static constexpr Color BTN_YELLOW_INNER     = {220, 200,  50, 255 };
static constexpr Color BTN_YELLOW_HIGHLIGHT = {255, 240, 100, 255 };

// Media buttons — dark grey with subtle tint
static constexpr Color BTN_MEDIA_OUTER     = { 60,  60,  65, 255 };
static constexpr Color BTN_MEDIA_INNER     = {100, 100, 108, 255 };
static constexpr Color BTN_MEDIA_HIGHLIGHT = {150, 150, 160, 255 };

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

static bool cd32_enabled = false;
static bool cd32_initialized = false;

// SDL Textures (non-OpenGL)
static SDL_Texture* stick_base_tex = nullptr;
static SDL_Texture* knob_tex = nullptr;
static SDL_Texture* btn_red_tex = nullptr;
static SDL_Texture* btn_blue_tex = nullptr;
static SDL_Texture* btn_green_tex = nullptr;
static SDL_Texture* btn_yellow_tex = nullptr;
static SDL_Texture* btn_play_tex = nullptr;
static SDL_Texture* btn_rwd_tex = nullptr;
static SDL_Texture* btn_ffw_tex = nullptr;

// SDL Surfaces (kept for GL upload)
static SDL_Surface* stick_base_surface = nullptr;
static SDL_Surface* knob_surface = nullptr;
static SDL_Surface* btn_red_surface = nullptr;
static SDL_Surface* btn_blue_surface = nullptr;
static SDL_Surface* btn_green_surface = nullptr;
static SDL_Surface* btn_yellow_surface = nullptr;
static SDL_Surface* btn_play_surface = nullptr;
static SDL_Surface* btn_rwd_surface = nullptr;
static SDL_Surface* btn_ffw_surface = nullptr;

#ifdef USE_OPENGL
static GLuint gl_stick_base_tex = 0;
static GLuint gl_knob_tex = 0;
static GLuint gl_btn_red_tex = 0;
static GLuint gl_btn_blue_tex = 0;
static GLuint gl_btn_green_tex = 0;
static GLuint gl_btn_yellow_tex = 0;
static GLuint gl_btn_play_tex = 0;
static GLuint gl_btn_rwd_tex = 0;
static GLuint gl_btn_ffw_tex = 0;
static bool cd32_gl_initialized = false;
#endif

// Layout rectangles
static SDL_Rect dpad_rect = {};
static SDL_Rect btn_red_rect = {};
static SDL_Rect btn_blue_rect = {};
static SDL_Rect btn_green_rect = {};
static SDL_Rect btn_yellow_rect = {};
static SDL_Rect btn_play_rect = {};
static SDL_Rect btn_rwd_rect = {};
static SDL_Rect btn_ffw_rect = {};

// Center/radius for hit-testing
static int dpad_cx = 0, dpad_cy = 0, dpad_hit_radius = 0;
static int btn_red_cx = 0, btn_red_cy = 0, btn_red_hit_r = 0;
static int btn_blue_cx = 0, btn_blue_cy = 0, btn_blue_hit_r = 0;
static int btn_green_cx = 0, btn_green_cy = 0, btn_green_hit_r = 0;
static int btn_yellow_cx = 0, btn_yellow_cy = 0, btn_yellow_hit_r = 0;
static int btn_play_cx = 0, btn_play_cy = 0, btn_play_hit_r = 0;
static int btn_rwd_cx = 0, btn_rwd_cy = 0, btn_rwd_hit_r = 0;
static int btn_ffw_cx = 0, btn_ffw_cy = 0, btn_ffw_hit_r = 0;

// D-pad state
static bool joy_up = false, joy_down = false, joy_left = false, joy_right = false;
static bool prev_up = false, prev_down = false, prev_left = false, prev_right = false;

// Button state
static bool joy_red = false, joy_blue = false, joy_green = false, joy_yellow = false;
static bool joy_play = false, joy_rwd = false, joy_ffw = false;
static bool prev_red = false, prev_blue = false, prev_green = false, prev_yellow = false;
static bool prev_play = false, prev_rwd = false, prev_ffw = false;

// Knob tracking
static float knob_offset_x = 0.0f;
static float knob_offset_y = 0.0f;
static bool knob_active = false;

// Multi-touch tracking
enum ControlType {
	CTL_NONE, CTL_DPAD,
	CTL_RED, CTL_BLUE, CTL_GREEN, CTL_YELLOW,
	CTL_PLAY, CTL_RWD, CTL_FFW
};

struct FingerTrack {
	SDL_FingerID id;
	ControlType control;
};
static std::vector<FingerTrack> active_fingers;

static int screen_w = 0, screen_h = 0;
static SDL_Rect cached_game_rect = {};

// CD32 pad button indices — must match the device registration order.
// These are the button numbers passed to setjoybuttonstate().
static constexpr int CD32_BTN_RED    = 0;
static constexpr int CD32_BTN_BLUE   = 1;
static constexpr int CD32_BTN_GREEN  = 2;
static constexpr int CD32_BTN_YELLOW = 3;
static constexpr int CD32_BTN_PLAY   = 4;
static constexpr int CD32_BTN_RWD    = 5;
static constexpr int CD32_BTN_FFW    = 6;

// ---------------------------------------------------------------------------
// Drawing helpers (same as on_screen_joystick — simple procedural shapes)
// ---------------------------------------------------------------------------

static void fill_circle(SDL_Surface* s, int cx, int cy, int radius, Color col)
{
	uint32_t color = SDL_MapSurfaceRGBA(s, col.r, col.g, col.b, col.a);
	auto* pixels = static_cast<uint32_t*>(s->pixels);
	int pitch = s->pitch / 4;
	int r2 = radius * radius;

	int y0 = std::max(0, cy - radius);
	int y1 = std::min(s->h - 1, cy + radius);
	for (int y = y0; y <= y1; y++) {
		int dy = y - cy;
		int dx_max = static_cast<int>(std::sqrt(static_cast<float>(r2 - dy * dy)));
		int x0 = std::max(0, cx - dx_max);
		int x1 = std::min(s->w - 1, cx + dx_max);
		for (int x = x0; x <= x1; x++) {
			pixels[y * pitch + x] = color;
		}
	}
}

static void fill_circle_gradient(SDL_Surface* s, int cx, int cy, int radius,
	Color outer, Color inner, Color glint)
{
	auto* pixels = static_cast<uint32_t*>(s->pixels);
	int pitch = s->pitch / 4;
	float r = static_cast<float>(radius);

	int y0 = std::max(0, cy - radius);
	int y1 = std::min(s->h - 1, cy + radius);
	for (int y = y0; y <= y1; y++) {
		int dy = y - cy;
		int dx_max = static_cast<int>(std::sqrt(r * r - static_cast<float>(dy * dy)));
		int x0 = std::max(0, cx - dx_max);
		int x1 = std::min(s->w - 1, cx + dx_max);
		for (int x = x0; x <= x1; x++) {
			int dx = x - cx;
			float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
			float t = dist / r;

			uint8_t cr = static_cast<uint8_t>(inner.r + (outer.r - inner.r) * t);
			uint8_t cg = static_cast<uint8_t>(inner.g + (outer.g - inner.g) * t);
			uint8_t cb = static_cast<uint8_t>(inner.b + (outer.b - inner.b) * t);
			uint8_t ca = static_cast<uint8_t>(inner.a + (outer.a - inner.a) * t);

			float highlight = std::max(0.0f, 1.0f - dist / (r * 0.5f));
			float angle = std::atan2(static_cast<float>(dy), static_cast<float>(dx));
			float dir_factor = std::max(0.0f, -std::cos(angle + 0.7f)) * highlight * 0.4f;
			cr = static_cast<uint8_t>(std::min(255.0f, cr + (glint.r - cr) * dir_factor));
			cg = static_cast<uint8_t>(std::min(255.0f, cg + (glint.g - cg) * dir_factor));
			cb = static_cast<uint8_t>(std::min(255.0f, cb + (glint.b - cb) * dir_factor));

			pixels[y * pitch + x] = SDL_MapSurfaceRGBA(s, cr, cg, cb, ca);
		}
	}
}

// ---------------------------------------------------------------------------
// Pixel-art font bitmaps (5x7) for button labels and media symbols
// ---------------------------------------------------------------------------

static const uint8_t font_R[7] = {
	0b11100,
	0b10010,
	0b10010,
	0b11100,
	0b10100,
	0b10010,
	0b10010,
};

static const uint8_t font_B[7] = {
	0b11100,
	0b10010,
	0b10010,
	0b11100,
	0b10010,
	0b10010,
	0b11100,
};

static const uint8_t font_G[7] = {
	0b01110,
	0b10000,
	0b10000,
	0b10110,
	0b10010,
	0b10010,
	0b01110,
};

static const uint8_t font_Y[7] = {
	0b10001,
	0b10001,
	0b01010,
	0b00100,
	0b00100,
	0b00100,
	0b00100,
};

static const uint8_t font_L[7] = {
	0b10000,
	0b10000,
	0b10000,
	0b10000,
	0b10000,
	0b10000,
	0b11110,
};

// Play triangle (▶)
static const uint8_t sym_play[7] = {
	0b10000,
	0b11000,
	0b11100,
	0b11110,
	0b11100,
	0b11000,
	0b10000,
};

// Rewind (◀◀) — double left triangles
static const uint8_t sym_rwd[7] = {
	0b00100,
	0b01100,
	0b11100,
	0b01100,
	0b00100,
	0b00000,
	0b00000,
};

// Fast-forward (▶▶) — double right triangles
static const uint8_t sym_ffw[7] = {
	0b10000,
	0b11000,
	0b11100,
	0b11000,
	0b10000,
	0b00000,
	0b00000,
};

static void draw_char(SDL_Surface* s, const uint8_t bitmap[7], int ox, int oy, int scale, Color col)
{
	uint32_t color = SDL_MapSurfaceRGBA(s, col.r, col.g, col.b, col.a);
	auto* pixels = static_cast<uint32_t*>(s->pixels);
	int pitch = s->pitch / 4;
	for (int row = 0; row < 7; row++) {
		for (int col_idx = 0; col_idx < 5; col_idx++) {
			if (bitmap[row] & (1 << (4 - col_idx))) {
				for (int sy = 0; sy < scale; sy++) {
					for (int sx = 0; sx < scale; sx++) {
						int x = ox + col_idx * scale + sx;
						int y = oy + row * scale + sy;
						if (x >= 0 && x < s->w && y >= 0 && y < s->h)
							pixels[y * pitch + x] = color;
					}
				}
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Surface generation
// ---------------------------------------------------------------------------

static SDL_Surface* create_stick_base_surface()
{
	const int sz = STICK_BASE_TEX_SIZE;
	SDL_Surface* surface = SDL_CreateSurface(sz, sz, SDL_PIXELFORMAT_ABGR8888);
	if (!surface) return nullptr;
	SDL_FillSurfaceRect(surface, nullptr, 0);

	int cx = sz / 2, cy = sz / 2;
	int base_r = sz / 2 - 4;

	fill_circle(surface, cx, cy, base_r, STICK_BASE_OUTER);
	fill_circle(surface, cx, cy, base_r - 2, STICK_BASE_BEVEL);

	// Inner well gradient
	{
		int well_r = base_r - 5;
		auto* pixels = static_cast<uint32_t*>(surface->pixels);
		int pitch = surface->pitch / 4;
		float fr = static_cast<float>(well_r);
		int y0 = std::max(0, cy - well_r);
		int y1 = std::min(sz - 1, cy + well_r);
		for (int y = y0; y <= y1; y++) {
			int dy = y - cy;
			int dx_max = static_cast<int>(std::sqrt(fr * fr - static_cast<float>(dy * dy)));
			int x0 = std::max(0, cx - dx_max);
			int x1 = std::min(sz - 1, cx + dx_max);
			for (int x = x0; x <= x1; x++) {
				int dx = x - cx;
				float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
				float t = dist / fr;
				uint8_t cr = static_cast<uint8_t>(STICK_BASE_WELL_IN.r + (STICK_BASE_WELL_OUT.r - STICK_BASE_WELL_IN.r) * t);
				uint8_t cg = static_cast<uint8_t>(STICK_BASE_WELL_IN.g + (STICK_BASE_WELL_OUT.g - STICK_BASE_WELL_IN.g) * t);
				uint8_t cb = static_cast<uint8_t>(STICK_BASE_WELL_IN.b + (STICK_BASE_WELL_OUT.b - STICK_BASE_WELL_IN.b) * t);
				pixels[y * pitch + x] = SDL_MapSurfaceRGBA(surface, cr, cg, cb, 255);
			}
		}
	}

	// 8 direction dots
	{
		static constexpr float PI = 3.14159265f;
		int dot_r = sz / 64;
		if (dot_r < 2) dot_r = 2;
		float dot_dist = (base_r - 5) * 0.70f;
		for (int i = 0; i < 8; i++) {
			float angle = i * PI / 4.0f;
			int dx = cx + static_cast<int>(std::cos(angle) * dot_dist);
			int dy = cy + static_cast<int>(std::sin(angle) * dot_dist);
			fill_circle(surface, dx, dy, dot_r, STICK_DIR_DOT);
		}
	}

	fill_circle(surface, cx, cy, sz / 16, STICK_CENTER_DOT);
	return surface;
}

static SDL_Surface* create_stick_knob_surface()
{
	const int sz = STICK_KNOB_TEX_SIZE;
	SDL_Surface* surface = SDL_CreateSurface(sz, sz, SDL_PIXELFORMAT_ABGR8888);
	if (!surface) return nullptr;
	SDL_FillSurfaceRect(surface, nullptr, 0);

	int cx = sz / 2, cy = sz / 2;
	int r = sz / 2 - 4;

	fill_circle_gradient(surface, cx, cy, r, KNOB_OUTER, KNOB_INNER, KNOB_GLINT);

	// Specular highlight
	{
		int spec_cx = cx - static_cast<int>(r * 0.25f);
		int spec_cy = cy - static_cast<int>(r * 0.25f);
		int spec_r = static_cast<int>(r * 0.15f);
		if (spec_r < 2) spec_r = 2;
		auto* pixels = static_cast<uint32_t*>(surface->pixels);
		int pitch = surface->pitch / 4;
		float fspec_r = static_cast<float>(spec_r);
		const auto* fmt = SDL_GetPixelFormatDetails(surface->format);
		if (!fmt) return surface;
		int y0 = std::max(0, spec_cy - spec_r);
		int y1 = std::min(sz - 1, spec_cy + spec_r);
		for (int y = y0; y <= y1; y++) {
			int dy = y - spec_cy;
			int dx_max = static_cast<int>(std::sqrt(fspec_r * fspec_r - static_cast<float>(dy * dy)));
			int x0 = std::max(0, spec_cx - dx_max);
			int x1 = std::min(sz - 1, spec_cx + dx_max);
			for (int x = x0; x <= x1; x++) {
				int dx = x - spec_cx;
				float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
				float t = dist / fspec_r;
				uint8_t alpha = static_cast<uint8_t>(200.0f * (1.0f - t));
				uint32_t existing = pixels[y * pitch + x];
				uint8_t er, eg, eb, ea;
				SDL_GetRGBA(existing, fmt, nullptr, &er, &eg, &eb, &ea);
				if (ea > 0) {
					float a = alpha / 255.0f;
					er = static_cast<uint8_t>(std::min(255.0f, er + (255 - er) * a));
					eg = static_cast<uint8_t>(std::min(255.0f, eg + (220 - eg) * a));
					eb = static_cast<uint8_t>(std::min(255.0f, eb + (220 - eb) * a));
					pixels[y * pitch + x] = SDL_MapSurfaceRGBA(surface, er, eg, eb, ea);
				}
			}
		}
	}

	return surface;
}

static SDL_Surface* create_button_surface(Color outer, Color inner, Color glint,
	const uint8_t* label_bitmap)
{
	const int sz = BUTTON_TEX_SIZE;
	SDL_Surface* surface = SDL_CreateSurface(sz, sz, SDL_PIXELFORMAT_ABGR8888);
	if (!surface) return nullptr;
	SDL_FillSurfaceRect(surface, nullptr, 0);

	int cx = sz / 2, cy = sz / 2;
	int r = sz / 2 - 4;

	// Dark housing ring
	Color housing = { 20, 20, 22, 255 };
	fill_circle(surface, cx, cy, r, housing);

	// Bezel
	Color bezel = { static_cast<uint8_t>(outer.r / 2), static_cast<uint8_t>(outer.g / 2),
		static_cast<uint8_t>(outer.b / 2), 255 };
	fill_circle(surface, cx, cy, r - 3, bezel);

	// Main button surface with gradient
	fill_circle_gradient(surface, cx, cy, r - 6, outer, inner, glint);

	// Specular highlight
	{
		int spec_cx = cx - static_cast<int>((r - 6) * 0.22f);
		int spec_cy = cy - static_cast<int>((r - 6) * 0.22f);
		int spec_r = static_cast<int>((r - 6) * 0.12f);
		if (spec_r < 2) spec_r = 2;
		auto* pixels = static_cast<uint32_t*>(surface->pixels);
		int pitch = surface->pitch / 4;
		float fspec_r = static_cast<float>(spec_r);
		const auto* fmt = SDL_GetPixelFormatDetails(surface->format);
		if (!fmt) return surface;
		int y0 = std::max(0, spec_cy - spec_r);
		int y1 = std::min(sz - 1, spec_cy + spec_r);
		for (int y = y0; y <= y1; y++) {
			int dy = y - spec_cy;
			int dx_max = static_cast<int>(std::sqrt(fspec_r * fspec_r - static_cast<float>(dy * dy)));
			int x0 = std::max(0, spec_cx - dx_max);
			int x1 = std::min(sz - 1, spec_cx + dx_max);
			for (int x = x0; x <= x1; x++) {
				int dx = x - spec_cx;
				float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
				float t = dist / fspec_r;
				uint8_t alpha = static_cast<uint8_t>(150.0f * (1.0f - t));
				uint32_t existing = pixels[y * pitch + x];
				uint8_t er, eg, eb, ea;
				SDL_GetRGBA(existing, fmt, nullptr, &er, &eg, &eb, &ea);
				if (ea > 0) {
					float a = alpha / 255.0f;
					er = static_cast<uint8_t>(std::min(255.0f, er + (255 - er) * a));
					eg = static_cast<uint8_t>(std::min(255.0f, eg + (255 - eg) * a));
					eb = static_cast<uint8_t>(std::min(255.0f, eb + (255 - eb) * a));
					pixels[y * pitch + x] = SDL_MapSurfaceRGBA(surface, er, eg, eb, ea);
				}
			}
		}
	}

	// Draw label character if provided
	if (label_bitmap) {
		Color text_col = { 255, 255, 255, 220 };
		int char_scale = sz / 32;
		if (char_scale < 1) char_scale = 1;
		int char_w = 5 * char_scale;
		int char_h = 7 * char_scale;
		int text_x = cx - char_w / 2;
		int text_y = cy - char_h / 2;
		draw_char(surface, label_bitmap, text_x, text_y, char_scale, text_col);
	}

	return surface;
}

// ---------------------------------------------------------------------------
// Shoulder button surface (rounded rectangle / pill shape)
// ---------------------------------------------------------------------------

static void fill_rounded_rect(SDL_Surface* s, int x0, int y0, int w, int h, int corner_r, Color col)
{
	uint32_t color = SDL_MapSurfaceRGBA(s, col.r, col.g, col.b, col.a);
	auto* pixels = static_cast<uint32_t*>(s->pixels);
	int pitch = s->pitch / 4;

	for (int y = y0; y < y0 + h; y++) {
		if (y < 0 || y >= s->h) continue;
		for (int x = x0; x < x0 + w; x++) {
			if (x < 0 || x >= s->w) continue;
			// Check if we're in a corner region
			bool in_shape = true;
			int cx_corner = 0, cy_corner = 0;
			if (x < x0 + corner_r && y < y0 + corner_r) {
				cx_corner = x0 + corner_r; cy_corner = y0 + corner_r;
			} else if (x >= x0 + w - corner_r && y < y0 + corner_r) {
				cx_corner = x0 + w - corner_r; cy_corner = y0 + corner_r;
			} else if (x < x0 + corner_r && y >= y0 + h - corner_r) {
				cx_corner = x0 + corner_r; cy_corner = y0 + h - corner_r;
			} else if (x >= x0 + w - corner_r && y >= y0 + h - corner_r) {
				cx_corner = x0 + w - corner_r; cy_corner = y0 + h - corner_r;
			} else {
				cx_corner = -1; // Not in a corner
			}
			if (cx_corner >= 0) {
				int dx = x - cx_corner;
				int dy = y - cy_corner;
				if (dx * dx + dy * dy > corner_r * corner_r)
					in_shape = false;
			}
			if (in_shape)
				pixels[y * pitch + x] = color;
		}
	}
}

static void fill_rounded_rect_gradient(SDL_Surface* s, int x0, int y0, int w, int h, int corner_r,
	Color outer, Color inner, Color glint)
{
	auto* pixels = static_cast<uint32_t*>(s->pixels);
	int pitch = s->pitch / 4;
	float half_h = h / 2.0f;

	for (int y = y0; y < y0 + h; y++) {
		if (y < 0 || y >= s->h) continue;
		for (int x = x0; x < x0 + w; x++) {
			if (x < 0 || x >= s->w) continue;
			// Corner test
			bool in_shape = true;
			int cx_corner = 0, cy_corner = 0;
			if (x < x0 + corner_r && y < y0 + corner_r) {
				cx_corner = x0 + corner_r; cy_corner = y0 + corner_r;
			} else if (x >= x0 + w - corner_r && y < y0 + corner_r) {
				cx_corner = x0 + w - corner_r; cy_corner = y0 + corner_r;
			} else if (x < x0 + corner_r && y >= y0 + h - corner_r) {
				cx_corner = x0 + corner_r; cy_corner = y0 + h - corner_r;
			} else if (x >= x0 + w - corner_r && y >= y0 + h - corner_r) {
				cx_corner = x0 + w - corner_r; cy_corner = y0 + h - corner_r;
			} else {
				cx_corner = -1;
			}
			if (cx_corner >= 0) {
				int dx = x - cx_corner;
				int dy = y - cy_corner;
				if (dx * dx + dy * dy > corner_r * corner_r)
					in_shape = false;
			}
			if (!in_shape) continue;

			// Vertical gradient: top = glint, middle = inner, bottom = outer
			float fy = static_cast<float>(y - y0);
			float t = fy / static_cast<float>(h);
			float dir_factor = (t < 0.5f) ? (1.0f - t * 2.0f) * 0.3f : 0.0f;
			float base_t = t;
			auto cr = static_cast<uint8_t>(outer.r + (inner.r - outer.r) * (1.0f - base_t));
			auto cg = static_cast<uint8_t>(outer.g + (inner.g - outer.g) * (1.0f - base_t));
			auto cb = static_cast<uint8_t>(outer.b + (inner.b - outer.b) * (1.0f - base_t));
			uint8_t ca = 255;
			cr = static_cast<uint8_t>(std::min(255.0f, cr + (glint.r - cr) * dir_factor));
			cg = static_cast<uint8_t>(std::min(255.0f, cg + (glint.g - cg) * dir_factor));
			cb = static_cast<uint8_t>(std::min(255.0f, cb + (glint.b - cb) * dir_factor));
			pixels[y * pitch + x] = SDL_MapSurfaceRGBA(s, cr, cg, cb, ca);
		}
	}
}

static SDL_Surface* create_shoulder_surface(Color outer, Color inner, Color glint,
	const uint8_t* label_bitmap)
{
	const int tw = SHOULDER_TEX_W;
	const int th = SHOULDER_TEX_H;
	SDL_Surface* surface = SDL_CreateSurface(tw, th, SDL_PIXELFORMAT_ABGR8888);
	if (!surface) return nullptr;
	SDL_FillSurfaceRect(surface, nullptr, 0);

	int corner_r = th / 4;

	// Dark housing
	Color housing = { 20, 20, 22, 255 };
	fill_rounded_rect(surface, 2, 2, tw - 4, th - 4, corner_r, housing);

	// Bezel
	Color bezel = { static_cast<uint8_t>(outer.r / 2), static_cast<uint8_t>(outer.g / 2),
		static_cast<uint8_t>(outer.b / 2), 255 };
	fill_rounded_rect(surface, 5, 5, tw - 10, th - 10, corner_r - 3, bezel);

	// Main gradient fill
	fill_rounded_rect_gradient(surface, 8, 8, tw - 16, th - 16, corner_r - 6, outer, inner, glint);

	// Draw label character if provided
	if (label_bitmap) {
		Color text_col = { 255, 255, 255, 220 };
		int char_scale = th / 16;
		if (char_scale < 1) char_scale = 1;
		int char_w = 5 * char_scale;
		int char_h = 7 * char_scale;
		int text_x = tw / 2 - char_w / 2;
		int text_y = th / 2 - char_h / 2;
		draw_char(surface, label_bitmap, text_x, text_y, char_scale, text_col);
	}

	return surface;
}

// ---------------------------------------------------------------------------
// Input injection
// ---------------------------------------------------------------------------

static void inject_directions()
{
	int dev = get_onscreen_cd32pad_device_index();
	if (dev < 0) return;

	constexpr int AXIS_MAX = 32767;

	bool x_changed = (joy_left != prev_left) || (joy_right != prev_right);
	bool y_changed = (joy_up != prev_up) || (joy_down != prev_down);

	if (x_changed) {
		int x = 0;
		if (joy_left)  x = -AXIS_MAX;
		if (joy_right) x =  AXIS_MAX;
		setjoystickstate(dev, 0, x, AXIS_MAX);
		prev_left = joy_left;
		prev_right = joy_right;
	}
	if (y_changed) {
		int y = 0;
		if (joy_up)   y = -AXIS_MAX;
		if (joy_down) y =  AXIS_MAX;
		setjoystickstate(dev, 1, y, AXIS_MAX);
		prev_up = joy_up;
		prev_down = joy_down;
	}
}

static void inject_button(int btn_index, bool current, bool& previous)
{
	if (current != previous) {
		int dev = get_onscreen_cd32pad_device_index();
		if (dev >= 0) {
			setjoybuttonstate(dev, btn_index, current ? 1 : 0);
		}
		previous = current;
	}
}

static void inject_all_buttons()
{
	inject_button(CD32_BTN_RED, joy_red, prev_red);
	inject_button(CD32_BTN_BLUE, joy_blue, prev_blue);
	inject_button(CD32_BTN_GREEN, joy_green, prev_green);
	inject_button(CD32_BTN_YELLOW, joy_yellow, prev_yellow);
	inject_button(CD32_BTN_PLAY, joy_play, prev_play);
	inject_button(CD32_BTN_RWD, joy_rwd, prev_rwd);
	inject_button(CD32_BTN_FFW, joy_ffw, prev_ffw);
}

// ---------------------------------------------------------------------------
// D-pad logic (same as on_screen_joystick)
// ---------------------------------------------------------------------------

static void update_dpad_from_position(int touch_x, int touch_y)
{
	int dx = touch_x - dpad_cx;
	int dy = touch_y - dpad_cy;
	float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
	float max_travel = dpad_hit_radius * KNOB_MAX_TRAVEL;

	if (dist > max_travel) {
		float scale = max_travel / dist;
		knob_offset_x = (dx * scale) / max_travel;
		knob_offset_y = (dy * scale) / max_travel;
	} else if (dist > 0.001f) {
		knob_offset_x = static_cast<float>(dx) / max_travel;
		knob_offset_y = static_cast<float>(dy) / max_travel;
	} else {
		knob_offset_x = 0.0f;
		knob_offset_y = 0.0f;
	}

	float deadzone_px = dpad_hit_radius * DPAD_DEADZONE;
	if (dist < deadzone_px) {
		joy_up = joy_down = joy_left = joy_right = false;
		inject_directions();
		return;
	}

	float angle = std::atan2(static_cast<float>(dy), static_cast<float>(dx));
	static constexpr float PI = 3.14159265f;
	static constexpr float SECTOR = PI / 4.0f;
	static constexpr float HALF_SECTOR = PI / 8.0f;

	float a = angle;
	if (a < 0) a += 2.0f * PI;
	int sector = static_cast<int>((a + HALF_SECTOR) / SECTOR) % 8;

	joy_right = (sector == 0 || sector == 1 || sector == 7);
	joy_left  = (sector == 3 || sector == 4 || sector == 5);
	joy_down  = (sector == 1 || sector == 2 || sector == 3);
	joy_up    = (sector == 5 || sector == 6 || sector == 7);

	inject_directions();
}

static void release_dpad()
{
	joy_up = joy_down = joy_left = joy_right = false;
	knob_offset_x = 0.0f;
	knob_offset_y = 0.0f;
	knob_active = false;
	inject_directions();
}

static void release_button(ControlType ctl)
{
	switch (ctl) {
	case CTL_RED:    joy_red = false; break;
	case CTL_BLUE:   joy_blue = false; break;
	case CTL_GREEN:  joy_green = false; break;
	case CTL_YELLOW: joy_yellow = false; break;
	case CTL_PLAY:   joy_play = false; break;
	case CTL_RWD:    joy_rwd = false; break;
	case CTL_FFW:    joy_ffw = false; break;
	default: return;
	}
	inject_all_buttons();
}

static SDL_Rect compute_knob_rect()
{
	int knob_size = static_cast<int>(dpad_rect.w * KNOB_SIZE_FRACTION);
	float max_travel_px = dpad_hit_radius * KNOB_MAX_TRAVEL;

	int knob_cx = dpad_cx + static_cast<int>(knob_offset_x * max_travel_px);
	int knob_cy = dpad_cy + static_cast<int>(knob_offset_y * max_travel_px);

	SDL_Rect r;
	r.x = knob_cx - knob_size / 2;
	r.y = knob_cy - knob_size / 2;
	r.w = knob_size;
	r.h = knob_size;
	return r;
}

// ---------------------------------------------------------------------------
// Finger tracking
// ---------------------------------------------------------------------------

static FingerTrack* find_finger(SDL_FingerID id)
{
	for (auto& f : active_fingers) {
		if (f.id == id) return &f;
	}
	return nullptr;
}

static void remove_finger(SDL_FingerID id)
{
	active_fingers.erase(
		std::remove_if(active_fingers.begin(), active_fingers.end(),
			[id](const FingerTrack& f) { return f.id == id; }),
		active_fingers.end());
}

static void release_existing_control(ControlType ctl)
{
	for (auto it = active_fingers.begin(); it != active_fingers.end(); ) {
		if (it->control == ctl) {
			it = active_fingers.erase(it);
		} else {
			++it;
		}
	}
	if (ctl == CTL_DPAD) {
		release_dpad();
	} else {
		release_button(ctl);
	}
}

static ControlType hit_test(int px, int py)
{
	// Check D-pad
	{
		int dx = px - dpad_cx;
		int dy = py - dpad_cy;
		if (dx * dx + dy * dy <= dpad_hit_radius * dpad_hit_radius)
			return CTL_DPAD;
	}
	// Check face buttons (with generous hit radius)
	auto check_btn = [&](int cx, int cy, int r, ControlType ctl) -> ControlType {
		int dx = px - cx;
		int dy = py - cy;
		if (dx * dx + dy * dy <= r * r) return ctl;
		return CTL_NONE;
	};
	ControlType hit;
	if ((hit = check_btn(btn_red_cx, btn_red_cy, btn_red_hit_r, CTL_RED)) != CTL_NONE) return hit;
	if ((hit = check_btn(btn_blue_cx, btn_blue_cy, btn_blue_hit_r, CTL_BLUE)) != CTL_NONE) return hit;
	if ((hit = check_btn(btn_green_cx, btn_green_cy, btn_green_hit_r, CTL_GREEN)) != CTL_NONE) return hit;
	if ((hit = check_btn(btn_yellow_cx, btn_yellow_cy, btn_yellow_hit_r, CTL_YELLOW)) != CTL_NONE) return hit;
	if ((hit = check_btn(btn_play_cx, btn_play_cy, btn_play_hit_r, CTL_PLAY)) != CTL_NONE) return hit;
	// Shoulder buttons use rectangle hit test (pill shape, wider than tall)
	auto check_rect_btn = [&](const SDL_Rect& rect, int pad, ControlType ctl) -> ControlType {
		if (px >= rect.x - pad && px < rect.x + rect.w + pad &&
			py >= rect.y - pad && py < rect.y + rect.h + pad)
			return ctl;
		return CTL_NONE;
	};
	if ((hit = check_rect_btn(btn_rwd_rect, btn_rwd_rect.h / 6, CTL_RWD)) != CTL_NONE) return hit;
	if ((hit = check_rect_btn(btn_ffw_rect, btn_ffw_rect.h / 6, CTL_FFW)) != CTL_NONE) return hit;
	return CTL_NONE;
}

#ifdef USE_OPENGL
static void cleanup_cd32_gl()
{
	auto del = [](GLuint& t) { if (t) { glDeleteTextures(1, &t); t = 0; } };
	del(gl_stick_base_tex);
	del(gl_knob_tex);
	del(gl_btn_red_tex);
	del(gl_btn_blue_tex);
	del(gl_btn_green_tex);
	del(gl_btn_yellow_tex);
	del(gl_btn_play_tex);
	del(gl_btn_rwd_tex);
	del(gl_btn_ffw_tex);
	// Don't clean up the shared shader — on_screen_joystick_gl owns it
	cd32_gl_initialized = false;
}
#endif

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void on_screen_cd32pad_init(SDL_Renderer* renderer)
{
	if (cd32_initialized) {
		on_screen_cd32pad_quit();
	}

	// Generate surfaces
	stick_base_surface = create_stick_base_surface();
	knob_surface = create_stick_knob_surface();
	btn_red_surface    = create_button_surface(BTN_RED_OUTER, BTN_RED_INNER, BTN_RED_HIGHLIGHT, font_R);
	btn_blue_surface   = create_button_surface(BTN_BLUE_OUTER, BTN_BLUE_INNER, BTN_BLUE_HIGHLIGHT, font_B);
	btn_green_surface  = create_button_surface(BTN_GREEN_OUTER, BTN_GREEN_INNER, BTN_GREEN_HIGHLIGHT, font_G);
	btn_yellow_surface = create_button_surface(BTN_YELLOW_OUTER, BTN_YELLOW_INNER, BTN_YELLOW_HIGHLIGHT, font_Y);
	btn_play_surface   = create_button_surface(BTN_MEDIA_OUTER, BTN_MEDIA_INNER, BTN_MEDIA_HIGHLIGHT, sym_play);
	btn_rwd_surface    = create_shoulder_surface(BTN_MEDIA_OUTER, BTN_MEDIA_INNER, BTN_MEDIA_HIGHLIGHT, font_L);
	btn_ffw_surface    = create_shoulder_surface(BTN_MEDIA_OUTER, BTN_MEDIA_INNER, BTN_MEDIA_HIGHLIGHT, font_R);

#ifndef USE_OPENGL
	if (renderer) {
		auto make_tex = [&](SDL_Surface* s) -> SDL_Texture* {
			if (!s) return nullptr;
			SDL_Texture* t = SDL_CreateTextureFromSurface(renderer, s);
			if (t) SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
			return t;
		};
		stick_base_tex = make_tex(stick_base_surface);
		knob_tex       = make_tex(knob_surface);
		btn_red_tex    = make_tex(btn_red_surface);
		btn_blue_tex   = make_tex(btn_blue_surface);
		btn_green_tex  = make_tex(btn_green_surface);
		btn_yellow_tex = make_tex(btn_yellow_surface);
		btn_play_tex   = make_tex(btn_play_surface);
		btn_rwd_tex    = make_tex(btn_rwd_surface);
		btn_ffw_tex    = make_tex(btn_ffw_surface);
	}
#endif

	// Reset state
	joy_up = joy_down = joy_left = joy_right = false;
	prev_up = prev_down = prev_left = prev_right = false;
	joy_red = joy_blue = joy_green = joy_yellow = false;
	joy_play = joy_rwd = joy_ffw = false;
	prev_red = prev_blue = prev_green = prev_yellow = false;
	prev_play = prev_rwd = prev_ffw = false;
	knob_offset_x = 0.0f;
	knob_offset_y = 0.0f;
	knob_active = false;
	active_fingers.clear();

	cd32_initialized = true;
}

void on_screen_cd32pad_quit()
{
	// Release held inputs
	if (joy_up || joy_down || joy_left || joy_right) {
		joy_up = joy_down = joy_left = joy_right = false;
		inject_directions();
	}
	joy_red = joy_blue = joy_green = joy_yellow = false;
	joy_play = joy_rwd = joy_ffw = false;
	inject_all_buttons();

	auto destroy_tex = [](SDL_Texture*& t) { if (t) { SDL_DestroyTexture(t); t = nullptr; } };
	destroy_tex(stick_base_tex);
	destroy_tex(knob_tex);
	destroy_tex(btn_red_tex);
	destroy_tex(btn_blue_tex);
	destroy_tex(btn_green_tex);
	destroy_tex(btn_yellow_tex);
	destroy_tex(btn_play_tex);
	destroy_tex(btn_rwd_tex);
	destroy_tex(btn_ffw_tex);

	auto destroy_surf = [](SDL_Surface*& s) { if (s) { SDL_DestroySurface(s); s = nullptr; } };
	destroy_surf(stick_base_surface);
	destroy_surf(knob_surface);
	destroy_surf(btn_red_surface);
	destroy_surf(btn_blue_surface);
	destroy_surf(btn_green_surface);
	destroy_surf(btn_yellow_surface);
	destroy_surf(btn_play_surface);
	destroy_surf(btn_rwd_surface);
	destroy_surf(btn_ffw_surface);

	knob_offset_x = 0.0f;
	knob_offset_y = 0.0f;
	knob_active = false;

#ifdef USE_OPENGL
	cleanup_cd32_gl();
#endif

	active_fingers.clear();
	cd32_initialized = false;
}

bool on_screen_cd32pad_is_enabled()
{
	return false;
}

void on_screen_cd32pad_set_enabled(bool enabled)
{
	cd32_enabled = enabled;
	if (enabled) {
		int dev = get_onscreen_cd32pad_device_index();
		if (dev >= 0) {
			int target_id = JSEM_JOYS + dev;
			changed_prefs.jports[1].id = target_id;
			changed_prefs.jports[1].mode = JSEM_MODE_JOYSTICK_CD32;
			currprefs.jports[1].id = target_id;
			currprefs.jports[1].mode = JSEM_MODE_JOYSTICK_CD32;
			inputdevice_config_change();
			joystick_refresh_needed = true;
		}
	}
	else if (cd32_initialized) {
		joy_up = joy_down = joy_left = joy_right = false;
		joy_red = joy_blue = joy_green = joy_yellow = false;
		joy_play = joy_rwd = joy_ffw = false;
		knob_offset_x = 0.0f;
		knob_offset_y = 0.0f;
		knob_active = false;
		inject_directions();
		inject_all_buttons();
		active_fingers.clear();
	}
}

void on_screen_cd32pad_update_layout(int sw, int sh, const SDL_Rect& game_rect)
{
	screen_w = sw;
	screen_h = sh;

	int shorter = std::min(sw, sh);
	int margin = static_cast<int>(shorter * EDGE_MARGIN_FRACTION);

	// --- D-pad (left side, vertically centered) ---
	int dpad_size = static_cast<int>(shorter * DPAD_SIZE_FRACTION);
	int left_space = game_rect.x;
	if (left_space > dpad_size + margin * 2) {
		dpad_rect.x = (left_space - dpad_size) / 2;
	} else {
		dpad_rect.x = margin;
	}
	dpad_rect.y = (sh - dpad_size) / 2;
	dpad_rect.w = dpad_size;
	dpad_rect.h = dpad_size;
	dpad_cx = dpad_rect.x + dpad_size / 2;
	dpad_cy = dpad_rect.y + dpad_size / 2;
	dpad_hit_radius = dpad_size / 2;

	// --- Face buttons (right side, diamond layout) ---
	int face_size = static_cast<int>(shorter * FACE_BTN_SIZE_FRACTION);
	int spacing = static_cast<int>(shorter * DIAMOND_SPACING_FRACTION);
	int step = face_size + spacing; // center-to-center distance in diamond

	// Diamond center position — ensure Red (at +step right) stays on screen
	int right_start = game_rect.x + game_rect.w;
	int right_space = sw - right_start;
	// The rightmost point is diamond_cx + step + face_size/2
	// So diamond_cx must be <= sw - step - face_size/2 - margin
	int max_cx = sw - step - face_size / 2 - margin;
	int ideal_cx = right_start + right_space / 2;
	int diamond_cx = (ideal_cx < max_cx) ? ideal_cx : max_cx;
	int diamond_cy = sh / 2 - static_cast<int>(shorter * MEDIA_GAP_FRACTION);

	// Green = top, Yellow = left, Red = right, Blue = bottom
	auto set_btn = [&](SDL_Rect& rect, int& cx, int& cy, int& hit_r, int off_x, int off_y) {
		cx = diamond_cx + off_x;
		cy = diamond_cy + off_y;
		rect.x = cx - face_size / 2;
		rect.y = cy - face_size / 2;
		rect.w = face_size;
		rect.h = face_size;
		hit_r = face_size / 2 + face_size / 8;
	};

	set_btn(btn_green_rect,  btn_green_cx,  btn_green_cy,  btn_green_hit_r,  0, -step);
	set_btn(btn_yellow_rect, btn_yellow_cx, btn_yellow_cy, btn_yellow_hit_r, -step, 0);
	set_btn(btn_red_rect,    btn_red_cx,    btn_red_cy,    btn_red_hit_r,    step, 0);
	set_btn(btn_blue_rect,   btn_blue_cx,   btn_blue_cy,   btn_blue_hit_r,   0, step);

	// --- Media buttons ---
	// Play button: small circle centered below Blue
	int media_size = static_cast<int>(shorter * MEDIA_BTN_SIZE_FRACTION);
	int media_y = btn_blue_cy + face_size / 2 + static_cast<int>(shorter * MEDIA_GAP_FRACTION);
	btn_play_rect.x = diamond_cx - media_size / 2;
	btn_play_rect.y = media_y;
	btn_play_rect.w = media_size;
	btn_play_rect.h = media_size;
	btn_play_cx = btn_play_rect.x + media_size / 2;
	btn_play_cy = btn_play_rect.y + media_size / 2;
	btn_play_hit_r = media_size / 2 + media_size / 6;

	// --- Shoulder buttons (L/R — pill shape, left/right of Green) ---
	int shoulder_h = static_cast<int>(face_size * 0.45f);
	int shoulder_w = static_cast<int>(shoulder_h * 2.0f);
	int shoulder_gap = spacing / 2;
	int shoulder_y = btn_green_cy - face_size / 2 - shoulder_h - shoulder_gap;

	// L button: right-aligned to left edge of Green button
	btn_rwd_rect.w = shoulder_w;
	btn_rwd_rect.h = shoulder_h;
	btn_rwd_rect.x = btn_green_cx - face_size / 2 - shoulder_gap - shoulder_w;
	btn_rwd_rect.y = shoulder_y;
	btn_rwd_cx = btn_rwd_rect.x + shoulder_w / 2;
	btn_rwd_cy = btn_rwd_rect.y + shoulder_h / 2;
	btn_rwd_hit_r = shoulder_w / 2; // generous hit area

	// R button: left-aligned to right edge of Green button
	btn_ffw_rect.w = shoulder_w;
	btn_ffw_rect.h = shoulder_h;
	btn_ffw_rect.x = btn_green_cx + face_size / 2 + shoulder_gap;
	btn_ffw_rect.y = shoulder_y;
	btn_ffw_cx = btn_ffw_rect.x + shoulder_w / 2;
	btn_ffw_cy = btn_ffw_rect.y + shoulder_h / 2;
	btn_ffw_hit_r = shoulder_w / 2;
}

// ---------------------------------------------------------------------------
// SDL Rendering
// ---------------------------------------------------------------------------

void on_screen_cd32pad_redraw(SDL_Renderer* renderer)
{
	if (!cd32_enabled || !cd32_initialized) return;
	if (!stick_base_tex || !knob_tex) return;

	// Auto-recalculate layout
	{
		int sw = 0, sh = 0;
		SDL_GetCurrentRenderOutputSize(renderer, &sw, &sh);
		const auto& rq = g_renderer->render_quad;
		if (sw > 0 && sh > 0 && rq.w > 0 && rq.h > 0) {
			if (sw != screen_w || sh != screen_h ||
				rq.x != cached_game_rect.x || rq.y != cached_game_rect.y ||
				rq.w != cached_game_rect.w || rq.h != cached_game_rect.h)
			{
				on_screen_cd32pad_update_layout(sw, sh, rq);
				cached_game_rect = rq;
			}
		}
	}

	// D-pad base
	{
		uint8_t alpha = knob_active ? ALPHA_PRESSED : ALPHA_NORMAL;
		SDL_SetTextureAlphaMod(stick_base_tex, alpha);
		SDL_SetTextureColorMod(stick_base_tex, 255, 255, 255);
		SDL_FRect fr = rect_to_frect(&dpad_rect);
		SDL_RenderTexture(renderer, stick_base_tex, nullptr, &fr);
	}

	// D-pad knob
	{
		SDL_Rect knob_rect = compute_knob_rect();
		if (knob_active) {
			SDL_Rect shadow = knob_rect;
			shadow.x += 2; shadow.y += 3; shadow.w += 2; shadow.h += 2;
			SDL_SetTextureAlphaMod(knob_tex, 60);
			SDL_SetTextureColorMod(knob_tex, 0, 0, 0);
			SDL_FRect fr = rect_to_frect(&shadow);
			SDL_RenderTexture(renderer, knob_tex, nullptr, &fr);
		}
		uint8_t knob_alpha = knob_active ? 240 : ALPHA_NORMAL;
		SDL_SetTextureAlphaMod(knob_tex, knob_alpha);
		SDL_SetTextureColorMod(knob_tex, 255, 255, 255);
		SDL_FRect fr = rect_to_frect(&knob_rect);
		SDL_RenderTexture(renderer, knob_tex, nullptr, &fr);
	}

	// Face buttons
	auto draw_btn = [&](SDL_Texture* tex, const SDL_Rect& rect, bool pressed,
		uint8_t pr, uint8_t pg, uint8_t pb) {
		if (!tex) return;
		uint8_t alpha = pressed ? ALPHA_PRESSED : ALPHA_NORMAL;
		SDL_SetTextureAlphaMod(tex, alpha);
		if (pressed) {
			SDL_SetTextureColorMod(tex, pr, pg, pb);
		} else {
			SDL_SetTextureColorMod(tex, 255, 255, 255);
		}
		SDL_FRect fr = rect_to_frect(&rect);
		SDL_RenderTexture(renderer, tex, nullptr, &fr);
	};

	draw_btn(btn_red_tex,    btn_red_rect,    joy_red,    255, 200, 200);
	draw_btn(btn_blue_tex,   btn_blue_rect,   joy_blue,   200, 200, 255);
	draw_btn(btn_green_tex,  btn_green_rect,  joy_green,  200, 255, 200);
	draw_btn(btn_yellow_tex, btn_yellow_rect, joy_yellow, 255, 255, 200);

	// Media buttons
	draw_btn(btn_play_tex, btn_play_rect, joy_play, 200, 255, 200);
	draw_btn(btn_rwd_tex,  btn_rwd_rect,  joy_rwd,  220, 220, 230);
	draw_btn(btn_ffw_tex,  btn_ffw_rect,  joy_ffw,  220, 220, 230);
}

// ---------------------------------------------------------------------------
// OpenGL Rendering
// ---------------------------------------------------------------------------

#ifdef USE_OPENGL
void on_screen_cd32pad_redraw_gl(int drawable_w, int drawable_h, const SDL_Rect& game_rect)
{
	if (!cd32_enabled || !cd32_initialized) return;
	if (!stick_base_surface || !knob_surface) return;

	// Update layout if geometry changed
	if (drawable_w > 0 && drawable_h > 0 && game_rect.w > 0 && game_rect.h > 0) {
		if (drawable_w != screen_w || drawable_h != screen_h ||
			game_rect.x != cached_game_rect.x || game_rect.y != cached_game_rect.y ||
			game_rect.w != cached_game_rect.w || game_rect.h != cached_game_rect.h)
		{
			on_screen_cd32pad_update_layout(drawable_w, drawable_h, game_rect);
			cached_game_rect = game_rect;
		}
	}

	// Lazy-init GL resources (shared shader from on_screen_joystick_gl)
	if (!osj_init_gl_shader()) return;

	// Upload textures on first use
	auto ensure_tex = [](GLuint& t, SDL_Surface* s) {
		if (!t && s) t = osj_upload_surface_to_gl(s);
	};
	ensure_tex(gl_stick_base_tex, stick_base_surface);
	ensure_tex(gl_knob_tex, knob_surface);
	ensure_tex(gl_btn_red_tex, btn_red_surface);
	ensure_tex(gl_btn_blue_tex, btn_blue_surface);
	ensure_tex(gl_btn_green_tex, btn_green_surface);
	ensure_tex(gl_btn_yellow_tex, btn_yellow_surface);
	ensure_tex(gl_btn_play_tex, btn_play_surface);
	ensure_tex(gl_btn_rwd_tex, btn_rwd_surface);
	ensure_tex(gl_btn_ffw_tex, btn_ffw_surface);

	if (!gl_stick_base_tex || !gl_knob_tex) return;

	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glDisable(GL_SCISSOR_TEST);
	glViewport(0, 0, drawable_w, drawable_h);
	glUseProgram(osj_get_gl_program());
	glBindVertexArray(osj_get_gl_vao());
	glEnableVertexAttribArray(0);
	glDisableVertexAttribArray(1);
	glDisableVertexAttribArray(2);

	// D-pad
	{
		float alpha = knob_active ? (ALPHA_PRESSED / 255.0f) : (ALPHA_NORMAL / 255.0f);
		osj_render_gl_quad(gl_stick_base_tex, dpad_rect, drawable_w, drawable_h, alpha);
	}

	// Knob
	{
		SDL_Rect knob_rect = compute_knob_rect();
		if (knob_active) {
			SDL_Rect shadow = knob_rect;
			shadow.x += 2; shadow.y += 3; shadow.w += 2; shadow.h += 2;
			osj_render_gl_quad(gl_knob_tex, shadow, drawable_w, drawable_h, 0.23f);
		}
		float knob_alpha = knob_active ? 0.94f : (ALPHA_NORMAL / 255.0f);
		osj_render_gl_quad(gl_knob_tex, knob_rect, drawable_w, drawable_h, knob_alpha);
	}

	// Face buttons
	auto draw_gl_btn = [&](GLuint tex, const SDL_Rect& rect, bool pressed) {
		if (!tex) return;
		float alpha = pressed ? (ALPHA_PRESSED / 255.0f) : (ALPHA_NORMAL / 255.0f);
		osj_render_gl_quad(tex, rect, drawable_w, drawable_h, alpha);
	};

	draw_gl_btn(gl_btn_red_tex,    btn_red_rect,    joy_red);
	draw_gl_btn(gl_btn_blue_tex,   btn_blue_rect,   joy_blue);
	draw_gl_btn(gl_btn_green_tex,  btn_green_rect,  joy_green);
	draw_gl_btn(gl_btn_yellow_tex, btn_yellow_rect, joy_yellow);

	// Media buttons
	draw_gl_btn(gl_btn_play_tex, btn_play_rect, joy_play);
	draw_gl_btn(gl_btn_rwd_tex,  btn_rwd_rect,  joy_rwd);
	draw_gl_btn(gl_btn_ffw_tex,  btn_ffw_rect,  joy_ffw);

	// Restore GL state
	glDisableVertexAttribArray(0);
	glBindVertexArray(0);
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	glDisable(GL_BLEND);
	glUseProgram(0);
}
#endif

// ---------------------------------------------------------------------------
// Touch event handlers
// ---------------------------------------------------------------------------

bool on_screen_cd32pad_handle_finger_down(const SDL_Event& event, int window_w, int window_h)
{
	if (!cd32_enabled || !cd32_initialized) return false;

	// Stale-finger audit
	if (!active_fingers.empty()) {
		SDL_TouchID touch_id = event.tfinger.touchID;
		int num_fingers = 0;
		SDL_Finger** fingers = SDL_GetTouchFingers(touch_id, &num_fingers);
		if (fingers) {
			for (auto it = active_fingers.begin(); it != active_fingers.end(); ) {
				bool still_alive = false;
				for (int i = 0; i < num_fingers; i++) {
					if (fingers[i]->id == it->id) {
						still_alive = true;
						break;
					}
				}
				if (!still_alive) {
					ControlType stale_ctl = it->control;
					it = active_fingers.erase(it);
					if (stale_ctl == CTL_DPAD) release_dpad();
					else release_button(stale_ctl);
				} else {
					++it;
				}
			}
			SDL_free(fingers);
		}
	}

	int px = static_cast<int>(event.tfinger.x * window_w);
	int py = static_cast<int>(event.tfinger.y * window_h);

	ControlType ctl = hit_test(px, py);
	if (ctl == CTL_NONE) return false;

	// Release orphaned finger on same control
	bool already_tracked = std::any_of(active_fingers.begin(), active_fingers.end(),
		[ctl](const FingerTrack& f) { return f.control == ctl; });
	if (already_tracked) {
		release_existing_control(ctl);
	}

	FingerTrack ft;
	ft.id = event.tfinger.fingerID;
	ft.control = ctl;
	active_fingers.push_back(ft);

	switch (ctl) {
	case CTL_DPAD:
		knob_active = true;
		update_dpad_from_position(px, py);
		break;
	case CTL_RED:    joy_red = true;    inject_all_buttons(); break;
	case CTL_BLUE:   joy_blue = true;   inject_all_buttons(); break;
	case CTL_GREEN:  joy_green = true;  inject_all_buttons(); break;
	case CTL_YELLOW: joy_yellow = true; inject_all_buttons(); break;
	case CTL_PLAY:   joy_play = true;   inject_all_buttons(); break;
	case CTL_RWD:    joy_rwd = true;    inject_all_buttons(); break;
	case CTL_FFW:    joy_ffw = true;    inject_all_buttons(); break;
	default: break;
	}

	return true;
}

bool on_screen_cd32pad_handle_finger_up(const SDL_Event& event, int /*window_w*/, int /*window_h*/)
{
	if (!cd32_enabled || !cd32_initialized) return false;

	FingerTrack* ft = find_finger(event.tfinger.fingerID);
	if (!ft) return false;

	ControlType ctl = ft->control;
	remove_finger(event.tfinger.fingerID);

	if (ctl == CTL_DPAD) {
		release_dpad();
	} else {
		release_button(ctl);
	}

	return true;
}

bool on_screen_cd32pad_handle_finger_motion(const SDL_Event& event, int window_w, int window_h)
{
	if (!cd32_enabled || !cd32_initialized) return false;

	FingerTrack* ft = find_finger(event.tfinger.fingerID);
	if (!ft) return false;

	if (ft->control == CTL_DPAD) {
		int px = static_cast<int>(event.tfinger.x * window_w);
		int py = static_cast<int>(event.tfinger.y * window_h);

		int dx = px - dpad_cx;
		int dy = py - dpad_cy;
		float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
		float release_dist = dpad_hit_radius * DPAD_RELEASE_RADIUS;

		if (dist > release_dist) {
			release_dpad();
			remove_finger(event.tfinger.fingerID);
			return true;
		}

		update_dpad_from_position(px, py);
	}

	return true;
}
