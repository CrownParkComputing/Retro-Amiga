/*
 * protracker.cpp - a ProTracker replayer.
 *
 * Written rather than pulled in: every MOD player worth using is either GPL,
 * which this tree cannot take, or drags in a dependency for what is, in the
 * end, four channels of sample playback and a small effect set. The format was
 * designed to be replayed by a 7MHz 68000, so there is nothing here a modern
 * device notices.
 *
 * What it implements is ProTracker 2.3 as the trackers of the day actually
 * used it, not the full effect list:
 *
 *   0 arpeggio          1 slide up          2 slide down       3 tone portamento
 *   4 vibrato           5 porta + vslide    6 vibrato + vslide 7 tremolo
 *   9 sample offset     A volume slide      B position jump    C set volume
 *   D pattern break     E sub-effects       F speed / tempo
 *
 * The E sub-effects implemented are the ones music uses: fine slides, fine
 * volume slides, retrigger, note delay, note cut and pattern delay.
 *
 * Deliberately faithful in three places where being "correct" would sound
 * wrong:
 *
 *  - Periods are clamped to the Amiga's own 113..856 range, because tunes rely
 *    on slides hitting the rail and staying there.
 *  - Sample loops are the format's: a loop length of 2 bytes or less means "not
 *    looped", and a repeat of 1 word is the standard silent-loop idiom.
 *  - Effect state persists across rows per channel, which is what makes
 *    vibrato and portamento continue when the row says nothing.
 */

#include "protracker.h"

#include <cstdint>

#include <cmath>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr int kChannelsMax = 8;   /* 4ch and the 8ch clones */
constexpr int kSamples = 31;
constexpr int kRows = 64;

/* The Amiga's clock, from which every period becomes a frequency. */
constexpr double kPalClock = 7093789.2;

/* ProTracker's period table, finetune 0, octaves 1-3. Slides and portamento
   run on periods, so the table is only needed to turn a note into one. */
const uint16_t kPeriods[36] = {
	856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
	428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
	214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,
};

/* Sine table for vibrato and tremolo, as the format defines it. */
const uint8_t kSine[32] = {
	  0,  24,  49,  74,  97, 120, 141, 161,
	180, 197, 212, 224, 235, 244, 250, 253,
	255, 253, 250, 244, 235, 224, 212, 197,
	180, 161, 141, 120,  97,  74,  49,  24,
};

struct Sample
{
	std::vector<int8_t> data;
	int loop_start = 0;
	int loop_length = 0;     /* in samples; 0 means no loop */
	int volume = 64;
	int finetune = 0;        /* signed -8..7 */
};

struct Note
{
	int sample = 0;          /* 1-based, 0 = none */
	int period = 0;          /* 0 = none */
	int effect = 0;
	int param = 0;
};

struct Channel
{
	const Sample* sample = nullptr;
	int sample_index = 0;

	double position = 0;     /* in samples, fractional */
	double increment = 0;

	int period = 0;
	int volume = 0;

	/* Effect state, kept between rows on purpose. */
	int porta_target = 0;
	int porta_speed = 0;
	int vibrato_speed = 0;
	int vibrato_depth = 0;
	int vibrato_pos = 0;
	int tremolo_speed = 0;
	int tremolo_depth = 0;
	int tremolo_pos = 0;
	int arpeggio = 0;
	int sample_offset = 0;
	int retrigger = 0;
	int note_delay = 0;
	int note_cut = -1;

	int last_effect = 0;
	int last_param = 0;

	bool playing = false;
	int output_volume = 0;   /* after tremolo, what the mixer uses */
};

int clamp_int(int value, int low, int high)
{
	return value < low ? low : (value > high ? high : value);
}

uint16_t read_be16(const uint8_t* p)
{
	return static_cast<uint16_t>((p[0] << 8) | p[1]);
}

/* Number of channels implied by the format tag, or 0 if this is not a MOD.
   A 15-sample Soundtracker module has no tag at all, which is why an absent
   tag is treated as 4 channels rather than a failure. */
int channels_from_tag(const char* tag)
{
	if (!memcmp(tag, "M.K.", 4) || !memcmp(tag, "M!K!", 4) ||
		!memcmp(tag, "FLT4", 4) || !memcmp(tag, "4CHN", 4))
		return 4;
	if (!memcmp(tag, "6CHN", 4))
		return 6;
	if (!memcmp(tag, "8CHN", 4) || !memcmp(tag, "FLT8", 4) ||
		!memcmp(tag, "CD81", 4) || !memcmp(tag, "OKTA", 4))
		return 8;
	return 0;
}

} // namespace

struct ProTracker
{
	/* ---- module ---- */
	std::string title;
	Sample samples[kSamples];
	std::vector<uint8_t> order;      /* pattern per song position */
	std::vector<Note> patterns;      /* pattern * rows * channels, flat */
	int channels = 4;
	int pattern_count = 0;
	int restart = 0;

	/* ---- playback ---- */
	Channel channel[kChannelsMax];
	int sample_rate = 44100;
	int speed = 6;                   /* ticks per row */
	int tempo = 125;                 /* BPM */
	int tick = 0;
	int row = 0;
	int position = 0;
	int pattern_delay = 0;

	double samples_per_tick = 0;
	double tick_remainder = 0;

	bool loaded = false;
	bool finished = false;

	/* Peak of the last mixed block, 0..1, for the workbench equaliser. */
	float level = 0;

	const Note& note_at(int pattern, int r, int c) const
	{
		return patterns[(static_cast<size_t>(pattern) * kRows + r) *
			channels + c];
	}

	void set_tempo(int bpm)
	{
		tempo = bpm;
		/* The classic formula: a tick is 2.5/BPM seconds. */
		samples_per_tick = sample_rate * 2.5 / bpm;
	}
};

/* ---- loading ----------------------------------------------------------- */

ProTracker* protracker_load(const void* bytes, size_t length)
{
	const auto* data = static_cast<const uint8_t*>(bytes);
	/* 20 title + 31 * 30 sample headers + 130 order block + 4 tag */
	if (!data || length < 1084)
		return nullptr;

	auto* mod = new ProTracker();

	char tag[5] = {};
	memcpy(tag, data + 1080, 4);
	mod->channels = channels_from_tag(tag);
	if (mod->channels == 0)
		mod->channels = 4;
	if (mod->channels > kChannelsMax) {
		delete mod;
		return nullptr;
	}

	mod->title.assign(reinterpret_cast<const char*>(data), 20);
	mod->title = mod->title.c_str(); /* trim at the first NUL */

	size_t offset = 20;
	for (int i = 0; i < kSamples; i++) {
		const uint8_t* header = data + offset;
		Sample& sample = mod->samples[i];

		const int length_words = read_be16(header + 22);
		sample.finetune = header[24] & 0x0f;
		if (sample.finetune > 7)
			sample.finetune -= 16;
		sample.volume = clamp_int(header[25], 0, 64);
		sample.loop_start = read_be16(header + 26) * 2;
		const int loop_words = read_be16(header + 28);

		/* A loop length of one word is the format's way of saying "no loop",
		   and every tracker wrote it that way. */
		sample.loop_length = loop_words > 1 ? loop_words * 2 : 0;
		sample.data.resize(static_cast<size_t>(length_words) * 2);

		offset += 30;
	}

	const int order_length = data[950];
	mod->restart = data[951];
	mod->order.assign(data + 952, data + 952 + 128);
	if (order_length > 0 && order_length <= 128)
		mod->order.resize(order_length);

	int highest = 0;
	for (const uint8_t entry : mod->order)
		highest = entry > highest ? entry : highest;
	mod->pattern_count = highest + 1;

	const size_t pattern_bytes =
		static_cast<size_t>(mod->pattern_count) * kRows * mod->channels * 4;
	if (1084 + pattern_bytes > length) {
		delete mod;
		return nullptr;
	}

	mod->patterns.resize(
		static_cast<size_t>(mod->pattern_count) * kRows * mod->channels);

	const uint8_t* p = data + 1084;
	for (size_t i = 0; i < mod->patterns.size(); i++, p += 4) {
		Note& note = mod->patterns[i];
		note.sample = (p[0] & 0xf0) | (p[2] >> 4);
		note.period = ((p[0] & 0x0f) << 8) | p[1];
		note.effect = p[2] & 0x0f;
		note.param = p[3];
	}

	/* Sample data follows the patterns, in header order. A truncated file is
	   common in the wild, so short reads shorten the sample rather than fail
	   the load. */
	size_t remaining = length - (1084 + pattern_bytes);
	const uint8_t* pcm = data + 1084 + pattern_bytes;
	for (auto& sample : mod->samples) {
		const size_t want = sample.data.size();
		const size_t take = want < remaining ? want : remaining;
		if (take)
			memcpy(sample.data.data(), pcm, take);
		if (take < want)
			memset(sample.data.data() + take, 0, want - take);
		pcm += take;
		remaining -= take;

		/* Clamp a loop that runs past the end, which truncation can cause. */
		if (sample.loop_length > 0) {
			const int total = static_cast<int>(sample.data.size());
			if (sample.loop_start >= total) {
				sample.loop_length = 0;
			} else if (sample.loop_start + sample.loop_length > total) {
				sample.loop_length = total - sample.loop_start;
			}
		}
	}

	mod->loaded = true;
	return mod;
}

void protracker_free(ProTracker* mod)
{
	delete mod;
}

const char* protracker_title(const ProTracker* mod)
{
	return mod && !mod->title.empty() ? mod->title.c_str() : "";
}

float protracker_level(const ProTracker* mod)
{
	return mod ? mod->level : 0.0f;
}

bool protracker_finished(const ProTracker* mod)
{
	return !mod || mod->finished;
}

/* ---- playback ---------------------------------------------------------- */

namespace {

/* Finetune shifts the period by moving along the table, which is what the
   hardware replayer did; it is not a multiply. */
int finetuned_period(int period, int finetune)
{
	if (finetune == 0 || period <= 0)
		return period;

	/* One finetune step is an eighth of a semitone - a sixteenth of the range
	   either way - which is a ninety-sixth of an octave. ProTracker shipped
	   sixteen precomputed period tables for this; the formula is those tables.
	   Stepping through the semitone table by the finetune value instead is a
	   whole semitone per step, which puts a sample tuned +7 a perfect fifth
	   sharp. It sounds plausible in isolation, which is what makes it worth
	   spelling out here. */
	return clamp_int(
		static_cast<int>(std::lround(period * std::pow(2.0, -finetune / 96.0))),
		113, 856);
}

void set_increment(ProTracker* mod, Channel& ch)
{
	if (ch.period <= 0) {
		ch.increment = 0;
		return;
	}
	const double frequency = kPalClock / (ch.period * 2.0);
	ch.increment = frequency / mod->sample_rate;
}

void trigger(ProTracker* mod, Channel& ch, int period, int offset)
{
	ch.position = offset;
	ch.playing = ch.sample != nullptr && !ch.sample->data.empty();
	if (period > 0) {
		ch.period = period;
		set_increment(mod, ch);
	}
}

void volume_slide(Channel& ch, int param)
{
	const int up = param >> 4;
	const int down = param & 0x0f;
	if (up)
		ch.volume = clamp_int(ch.volume + up, 0, 64);
	else if (down)
		ch.volume = clamp_int(ch.volume - down, 0, 64);
}

void tone_portamento(ProTracker* mod, Channel& ch)
{
	if (ch.porta_target == 0 || ch.porta_speed == 0)
		return;
	if (ch.period < ch.porta_target) {
		ch.period = ch.period + ch.porta_speed > ch.porta_target
			? ch.porta_target : ch.period + ch.porta_speed;
	} else if (ch.period > ch.porta_target) {
		ch.period = ch.period - ch.porta_speed < ch.porta_target
			? ch.porta_target : ch.period - ch.porta_speed;
	}
	set_increment(mod, ch);
}

/* Vibrato and tremolo share a waveform and a position; only what they modulate
   differs. */
int wave(int position, int depth)
{
	const int index = (position >> 2) & 0x1f;
	return (kSine[index] * depth) >> 7;
}

void apply_vibrato(ProTracker* mod, Channel& ch)
{
	if (ch.vibrato_depth == 0)
		return;
	const int delta = wave(ch.vibrato_pos, ch.vibrato_depth);
	const int period = ch.vibrato_pos < 128 ? ch.period + delta : ch.period - delta;

	const double frequency = kPalClock / (clamp_int(period, 113, 856) * 2.0);
	ch.increment = frequency / mod->sample_rate;

	ch.vibrato_pos = (ch.vibrato_pos + ch.vibrato_speed * 4) & 0xff;
}

void apply_tremolo(Channel& ch)
{
	if (ch.tremolo_depth == 0) {
		ch.output_volume = ch.volume;
		return;
	}
	const int delta = wave(ch.tremolo_pos, ch.tremolo_depth);
	ch.output_volume = clamp_int(
		ch.tremolo_pos < 128 ? ch.volume + delta : ch.volume - delta, 0, 64);
	ch.tremolo_pos = (ch.tremolo_pos + ch.tremolo_speed * 4) & 0xff;
}

/* Everything that happens on tick 0 of a row: the note itself. */
void start_row(ProTracker* mod, int& jump_position, int& jump_row)
{
	const int pattern = mod->order[mod->position];

	for (int c = 0; c < mod->channels; c++) {
		Channel& ch = mod->channel[c];
		const Note& note = mod->note_at(pattern, mod->row, c);

		ch.arpeggio = 0;
		ch.retrigger = 0;
		ch.note_delay = 0;
		ch.note_cut = -1;

		if (note.sample > 0 && note.sample <= kSamples) {
			ch.sample_index = note.sample;
			ch.sample = &mod->samples[note.sample - 1];
			/* A sample number alone resets the volume, even with no note. */
			ch.volume = ch.sample->volume;
		}

		int period = note.period;
		if (period > 0 && ch.sample)
			period = finetuned_period(period, ch.sample->finetune);

		const bool is_porta = note.effect == 0x3 || note.effect == 0x5;

		if (period > 0) {
			if (is_porta) {
				/* Portamento retunes towards the note instead of restarting
				   the sample - the whole point of the effect. */
				ch.porta_target = period;
			} else {
				const bool delayed =
					note.effect == 0xE && (note.param >> 4) == 0xD;
				if (delayed) {
					ch.note_delay = note.param & 0x0f;
					ch.porta_target = period;
				} else {
					trigger(mod, ch, period,
						note.effect == 0x9 ? ch.sample_offset : 0);
					ch.vibrato_pos = 0;
					ch.tremolo_pos = 0;
				}
			}
		}

		/* Effects that take hold on tick 0. */
		switch (note.effect) {
		case 0x0:
			ch.arpeggio = note.param;
			break;
		case 0x3:
			if (note.param)
				ch.porta_speed = note.param;
			break;
		case 0x4:
			if (note.param >> 4)
				ch.vibrato_speed = note.param >> 4;
			if (note.param & 0x0f)
				ch.vibrato_depth = note.param & 0x0f;
			break;
		case 0x7:
			if (note.param >> 4)
				ch.tremolo_speed = note.param >> 4;
			if (note.param & 0x0f)
				ch.tremolo_depth = note.param & 0x0f;
			break;
		case 0x9:
			/* The offset is remembered, because 900 repeats the last one. */
			if (note.param)
				ch.sample_offset = note.param * 256;
			if (period > 0)
				ch.position = ch.sample_offset;
			break;
		case 0xB:
			jump_position = note.param;
			break;
		case 0xC:
			ch.volume = clamp_int(note.param, 0, 64);
			break;
		case 0xD:
			/* The parameter is decimal, not hex - a genuine quirk of the
			   format, not a bug here. */
			jump_row = (note.param >> 4) * 10 + (note.param & 0x0f);
			break;
		case 0xE:
			switch (note.param >> 4) {
			case 0x1: /* fine slide up */
				ch.period = clamp_int(ch.period - (note.param & 0x0f), 113, 856);
				set_increment(mod, ch);
				break;
			case 0x2: /* fine slide down */
				ch.period = clamp_int(ch.period + (note.param & 0x0f), 113, 856);
				set_increment(mod, ch);
				break;
			case 0x9: /* retrigger */
				ch.retrigger = note.param & 0x0f;
				break;
			case 0xA: /* fine volume up */
				ch.volume = clamp_int(ch.volume + (note.param & 0x0f), 0, 64);
				break;
			case 0xB: /* fine volume down */
				ch.volume = clamp_int(ch.volume - (note.param & 0x0f), 0, 64);
				break;
			case 0xC: /* note cut */
				ch.note_cut = note.param & 0x0f;
				break;
			case 0xE: /* pattern delay, in rows */
				mod->pattern_delay = note.param & 0x0f;
				break;
			default:
				break;
			}
			break;
		case 0xF:
			if (note.param == 0)
				break;
			/* Under 32 is speed in ticks, 32 and over is BPM. Every tune
			   depends on this split. */
			if (note.param < 32)
				mod->speed = note.param;
			else
				mod->set_tempo(note.param);
			break;
		default:
			break;
		}

		ch.last_effect = note.effect;
		ch.last_param = note.param;
		ch.output_volume = ch.volume;
	}
}

/* Everything that happens on ticks 1..speed-1: the effects that move. */
void continue_row(ProTracker* mod)
{
	const int pattern = mod->order[mod->position];

	for (int c = 0; c < mod->channels; c++) {
		Channel& ch = mod->channel[c];
		const Note& note = mod->note_at(pattern, mod->row, c);
		ch.output_volume = ch.volume;

		switch (note.effect) {
		case 0x0:
			if (ch.arpeggio && ch.period > 0) {
				/* Cycles base, +x semitones, +y semitones each tick. */
				const int step = mod->tick % 3;
				const int semitones = step == 0 ? 0
					: (step == 1 ? (ch.arpeggio >> 4) : (ch.arpeggio & 0x0f));
				const double frequency =
					kPalClock / (ch.period * 2.0) * std::pow(2.0, semitones / 12.0);
				ch.increment = frequency / mod->sample_rate;
			}
			break;
		case 0x1:
			ch.period = clamp_int(ch.period - note.param, 113, 856);
			set_increment(mod, ch);
			break;
		case 0x2:
			ch.period = clamp_int(ch.period + note.param, 113, 856);
			set_increment(mod, ch);
			break;
		case 0x3:
			tone_portamento(mod, ch);
			break;
		case 0x4:
			apply_vibrato(mod, ch);
			break;
		case 0x5:
			tone_portamento(mod, ch);
			volume_slide(ch, note.param);
			ch.output_volume = ch.volume;
			break;
		case 0x6:
			apply_vibrato(mod, ch);
			volume_slide(ch, note.param);
			ch.output_volume = ch.volume;
			break;
		case 0x7:
			apply_tremolo(ch);
			break;
		case 0xA:
			volume_slide(ch, note.param);
			ch.output_volume = ch.volume;
			break;
		case 0xE:
			switch (note.param >> 4) {
			case 0x9: /* retrigger every n ticks */
				if (ch.retrigger > 0 && mod->tick % ch.retrigger == 0)
					trigger(mod, ch, 0, 0);
				break;
			case 0xC: /* note cut */
				if (mod->tick == ch.note_cut) {
					ch.volume = 0;
					ch.output_volume = 0;
				}
				break;
			case 0xD: /* note delay: the note lands mid-row */
				if (ch.note_delay > 0 && mod->tick == ch.note_delay) {
					trigger(mod, ch, ch.porta_target, 0);
					ch.vibrato_pos = 0;
					ch.tremolo_pos = 0;
				}
				break;
			default:
				break;
			}
			break;
		default:
			break;
		}
	}
}

void advance(ProTracker* mod, int jump_position, int jump_row)
{
	if (mod->pattern_delay > 0) {
		mod->pattern_delay--;
		return;
	}

	if (jump_position >= 0) {
		mod->position = jump_position;
		mod->row = jump_row >= 0 ? jump_row : 0;
		if (mod->position >= static_cast<int>(mod->order.size()))
			mod->finished = true;
		return;
	}
	if (jump_row >= 0) {
		mod->position++;
		mod->row = jump_row;
	} else {
		mod->row++;
		if (mod->row >= kRows) {
			mod->row = 0;
			mod->position++;
		}
	}

	if (mod->position >= static_cast<int>(mod->order.size())) {
		/* Loop rather than stop: this is background music, and a MOD's restart
		   position is where the composer meant it to come back to. */
		mod->position = mod->restart < static_cast<int>(mod->order.size())
			? mod->restart : 0;
	}
	if (mod->row >= kRows)
		mod->row = 0;
}

void run_tick(ProTracker* mod)
{
	int jump_position = -1;
	int jump_row = -1;

	if (mod->tick == 0) {
		start_row(mod, jump_position, jump_row);
	} else {
		continue_row(mod);
	}

	mod->tick++;
	if (mod->tick >= mod->speed) {
		mod->tick = 0;
		advance(mod, jump_position, jump_row);
	} else if (jump_position >= 0 || jump_row >= 0) {
		/* A jump on tick 0 still takes effect at the end of the row. */
		mod->tick = mod->speed - 1;
	}
}

} // namespace

void protracker_start(ProTracker* mod, int sample_rate)
{
	if (!mod)
		return;
	mod->sample_rate = sample_rate > 0 ? sample_rate : 44100;
	mod->speed = 6;
	mod->set_tempo(125);
	mod->tick = 0;
	mod->row = 0;
	mod->position = 0;
	mod->pattern_delay = 0;
	mod->tick_remainder = 0;
	mod->finished = false;
	for (auto& ch : mod->channel)
		ch = Channel{};
}

void protracker_render(ProTracker* mod, int16_t* out, int frames)
{
	if (!out || frames <= 0)
		return;
	memset(out, 0, static_cast<size_t>(frames) * 2 * sizeof(int16_t));
	if (!mod || !mod->loaded || mod->order.empty())
		return;

	int done = 0;
	float peak = 0;

	while (done < frames) {
		if (mod->tick_remainder <= 0) {
			run_tick(mod);
			mod->tick_remainder += mod->samples_per_tick;
		}

		const int chunk = static_cast<int>(
			mod->tick_remainder < frames - done ? mod->tick_remainder
											    : frames - done);
		const int count = chunk > 0 ? chunk : 1;

		for (int c = 0; c < mod->channels; c++) {
			Channel& ch = mod->channel[c];
			if (!ch.playing || !ch.sample || ch.sample->data.empty())
				continue;

			const Sample& sample = *ch.sample;
			const int total = static_cast<int>(sample.data.size());

			for (int i = 0; i < count; i++) {
				int index = static_cast<int>(ch.position);
				if (index >= total) {
					if (sample.loop_length > 0) {
						/* Wrap into the loop, keeping the fraction so a short
						   loop does not drift sharp. */
						const double over = ch.position - sample.loop_start;
						const double wrapped =
							std::fmod(over, static_cast<double>(sample.loop_length));
						ch.position = sample.loop_start + wrapped;
						index = static_cast<int>(ch.position);
					} else {
						ch.playing = false;
						break;
					}
				}

				const int value = sample.data[index] * ch.output_volume;

				/* Amiga stereo: channels 0 and 3 left, 1 and 2 right. Hard
				   panning is what the machine did, but it is fatiguing on
				   headphones, so this leans them 75/25 instead. */
				const bool left = (c % 4) == 0 || (c % 4) == 3;
				const int strong = value * 3 / 4;
				const int weak = value / 4;

				const int frame = (done + i) * 2;
				out[frame] = static_cast<int16_t>(clamp_int(
					out[frame] + (left ? strong : weak), -32768, 32767));
				out[frame + 1] = static_cast<int16_t>(clamp_int(
					out[frame + 1] + (left ? weak : strong), -32768, 32767));

				ch.position += ch.increment;
			}
		}

		for (int i = 0; i < count; i++) {
			const float magnitude =
				std::fabs(out[(done + i) * 2] / 32768.0f);
			peak = magnitude > peak ? magnitude : peak;
		}

		done += count;
		mod->tick_remainder -= count;
	}

	/* Decay rather than jump, so the equaliser it feeds does not flicker. */
	mod->level = peak > mod->level ? peak : mod->level * 0.85f + peak * 0.15f;
}
