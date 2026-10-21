// audio_out.rs - live host audio for the bridge.
//
// The core crate's own CpalSink lives behind the `frontend` feature, which
// also pulls in winit/egui -- the whole windowed desktop UI this build
// deliberately does not have. This is the same arrangement, standalone:
// Paula's 44.1 kHz f32 stereo frames go on a ring buffer; a cpal output
// stream drains it at whatever rate the device runs, with a small linear
// resample between.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use copperline::audio::{AudioSink, MIX_SAMPLE_RATE};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use ringbuf::traits::{Consumer, Observer, Producer, Split};
use ringbuf::HeapRb;

// ~1.5 s of stereo frames. Deep enough to ride out a scheduling stall,
// shallow enough that a flooded queue is caught by the drop-to-target
// trim rather than seconds of stale sound.
const BUFFER_FRAMES: usize = MIX_SAMPLE_RATE as usize * 3 / 2;
// How much backlog the callback tolerates before skipping forward.
// Past this, what is queued is lag, not buffer.
const TARGET_FRAMES: usize = MIX_SAMPLE_RATE as usize / 10;

pub struct LiveAudio {
    producer: ringbuf::HeapProd<(f32, f32)>,
    /// Keeps the stream alive; dropped when the run ends.
    _stream: cpal::Stream,
    /// Pausing the machine suspends output and clears the queue, so a
    /// resume does not play back a second of where it left off.
    suspended: Arc<AtomicBool>,
}

impl LiveAudio {
    /// Opens the default output device. None leaves the machine on a null
    /// sink: no audio device is a reason for silence, not for refusing to
    /// start a game.
    pub fn open(suspended: Arc<AtomicBool>) -> Option<Self> {
        let host = cpal::default_host();
        let device = host.default_output_device()?;
        let supported = device.default_output_config().ok()?;
        let channels = supported.channels().max(2);
        let out_rate = supported.sample_rate();
        let config = cpal::StreamConfig {
            channels,
            sample_rate: out_rate,
            buffer_size: cpal::BufferSize::Default,
        };

        let rb = HeapRb::<(f32, f32)>::new(BUFFER_FRAMES);
        let (producer, mut consumer) = rb.split();
        let underruns = Arc::new(AtomicU64::new(0));
        let suspended_cb = suspended.clone();
        let underruns_cb = underruns.clone();

        // Linear resampler state over the queued frames: `pos` is a
        // fractional read position between `prev` and `cur`.
        let step = MIX_SAMPLE_RATE as f64 / out_rate.max(1) as f64;
        let mut pos = 0.0f64;
        let mut prev = (0.0f32, 0.0f32);
        let mut cur = (0.0f32, 0.0f32);
        // Output does not start until this much has queued, so a game
        // does not open with a stutter of half-empty callbacks.
        let mut prebuffer = TARGET_FRAMES;

        let stream = device
            .build_output_stream(
                config,
                move |data: &mut [f32], _| {
                    let chans = channels as usize;
                    if suspended_cb.load(Ordering::Relaxed) {
                        consumer.clear();
                        pos = 0.0;
                        prebuffer = TARGET_FRAMES;
                        data.fill(0.0);
                        return;
                    }
                    // Too much queued is lag: keep only the tail.
                    let queued = consumer.occupied_len();
                    if queued > BUFFER_FRAMES / 2 {
                        consumer.skip(queued - TARGET_FRAMES);
                    }
                    for frame in data.chunks_mut(chans) {
                        let (l, r) = if prebuffer > 0 {
                            if consumer.occupied_len() >= prebuffer {
                                prebuffer = 0;
                            }
                            (0.0, 0.0)
                        } else {
                            while pos >= 1.0 {
                                prev = cur;
                                cur = consumer.try_pop().unwrap_or_else(|| {
                                    let n = underruns_cb.fetch_add(1, Ordering::Relaxed);
                                    // Every ~10 s of dry frames: the log
                                    // names the symptom without flooding.
                                    if n.is_multiple_of(MIX_SAMPLE_RATE as u64) {
                                        log::warn!("audio: {} underrun frames so far", n + 1);
                                    }
                                    (0.0, 0.0)
                                });
                                pos -= 1.0;
                            }
                            let t = pos as f32;
                            pos += step;
                            (prev.0 + (cur.0 - prev.0) * t, prev.1 + (cur.1 - prev.1) * t)
                        };
                        frame[0] = l;
                        frame[1] = r;
                        for extra in &mut frame[2..] {
                            *extra = 0.0;
                        }
                    }
                },
                move |err| {
                    log::warn!("copperline audio: stream error: {err}");
                },
                None,
            )
            .ok()?;
        stream.play().ok()?;
        Some(Self {
            producer,
            _stream: stream,
            suspended,
        })
    }
}

impl AudioSink for LiveAudio {
    fn push(&mut self, left: f32, right: f32) {
        if self.suspended.load(Ordering::Relaxed) {
            return;
        }
        // A full queue drops the newest frame; the callback's skip trims
        // the backlog back to target, so the queue cannot lag the clock.
        let _ = self.producer.try_push((left, right));
    }

    fn flush(&mut self) {}
}
