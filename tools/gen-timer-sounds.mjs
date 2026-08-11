#!/usr/bin/env node
// gen-timer-sounds.mjs — synthesize the rest/interval timer cue assets.
//
// Zero-dependency: writes 16-bit PCM mono WAV sine tones with short fade
// envelopes (no clicks), then — if ffmpeg is on PATH — transcodes them to the
// platform-native container each side wants:
//
//   Android  res/raw/prepare_beep.ogg      (Vorbis .ogg)
//            res/raw/timer_complete.ogg
//   iOS      Runner/Sounds/PrepareBeep.caf  (PCM .caf)
//            Runner/Sounds/TimerComplete.caf
//
// The two cues are deliberately DIFFERENT so a listener never confuses them:
//   prepare  = three short ~1200 Hz blips (the 3-2-1 count-in)
//   complete = a two-note rising chirp (880 Hz -> 1320 Hz), "done"
//
// The committed .wav files are the source of truth; .ogg/.caf are generated
// artifacts. Regenerate all of them with:  node tools/gen-timer-sounds.mjs
//
// ffmpeg one-liners this script runs (documented for reproduction by hand):
//   ffmpeg -y -i prepare_beep.wav   -c:a libvorbis -q:a 4 prepare_beep.ogg
//   ffmpeg -y -i timer_complete.wav -c:a libvorbis -q:a 4 timer_complete.ogg
//   ffmpeg -y -i prepare_beep.wav   -f caf -c:a pcm_s16le PrepareBeep.caf
//   ffmpeg -y -i timer_complete.wav -f caf -c:a pcm_s16le TimerComplete.caf
//
// If ffmpeg is unavailable, the .wav files are still written and BOTH platforms
// fall back to .wav (Android res/raw and iOS both accept .wav); the caller must
// then point the native channels at the .wav names. We prefer ogg/caf.

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ANDROID_RAW = join(ROOT, 'apps/mobile/android/app/src/main/res/raw');
const IOS_SOUNDS = join(ROOT, 'apps/mobile/ios/Runner/Sounds');

const SAMPLE_RATE = 44100;

/** Render a sequence of tone/silence segments into a Float32 sample buffer. */
function renderSegments(segments) {
  const samples = [];
  for (const seg of segments) {
    const count = Math.round((seg.ms / 1000) * SAMPLE_RATE);
    const fade = Math.min(Math.round(0.005 * SAMPLE_RATE), Math.floor(count / 2));
    for (let i = 0; i < count; i += 1) {
      if (seg.freq == null) {
        samples.push(0);
        continue;
      }
      // Linear fade in/out so each blip starts and ends at zero (no pop).
      let gain = seg.gain ?? 0.6;
      if (i < fade) gain *= i / fade;
      else if (i > count - fade) gain *= (count - i) / fade;
      samples.push(Math.sin((2 * Math.PI * seg.freq * i) / SAMPLE_RATE) * gain);
    }
  }
  return samples;
}

/** Encode Float32 [-1,1] samples as a 16-bit PCM mono WAV file buffer. */
function encodeWav(samples) {
  const dataLength = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataLength);
  buffer.write('RIFF', 0, 'ascii');
  buffer.writeUInt32LE(36 + dataLength, 4);
  buffer.write('WAVE', 8, 'ascii');
  buffer.write('fmt ', 12, 'ascii');
  buffer.writeUInt32LE(16, 16); // PCM chunk size
  buffer.writeUInt16LE(1, 20); // PCM format
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * 2, 28); // byte rate
  buffer.writeUInt16LE(2, 32); // block align
  buffer.writeUInt16LE(16, 34); // bits per sample
  buffer.write('data', 36, 'ascii');
  buffer.writeUInt32LE(dataLength, 40);
  let offset = 44;
  for (const sample of samples) {
    const clamped = Math.max(-1, Math.min(1, sample));
    buffer.writeInt16LE(Math.round(clamped * 32767), offset);
    offset += 2;
  }
  return buffer;
}

const PREPARE = [
  { freq: 1200, ms: 90, gain: 0.6 },
  { freq: null, ms: 110 },
  { freq: 1200, ms: 90, gain: 0.6 },
  { freq: null, ms: 110 },
  { freq: 1200, ms: 90, gain: 0.6 },
];

const COMPLETE = [
  { freq: 880, ms: 130, gain: 0.6 },
  { freq: 1320, ms: 220, gain: 0.6 },
];

function haveFfmpeg() {
  const probe = spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' });
  return probe.status === 0;
}

function ffmpeg(args) {
  const result = spawnSync('ffmpeg', ['-y', ...args], { stdio: 'inherit' });
  if (result.status !== 0) {
    throw new Error(`ffmpeg failed: ffmpeg ${args.join(' ')}`);
  }
}

function main() {
  mkdirSync(ANDROID_RAW, { recursive: true });
  mkdirSync(IOS_SOUNDS, { recursive: true });

  const cues = [
    { name: 'prepare_beep', ios: 'PrepareBeep', segments: PREPARE },
    { name: 'timer_complete', ios: 'TimerComplete', segments: COMPLETE },
  ];

  const wavPaths = {};
  for (const cue of cues) {
    const wav = encodeWav(renderSegments(cue.segments));
    const androidWav = join(ANDROID_RAW, `${cue.name}.wav`);
    writeFileSync(androidWav, wav);
    wavPaths[cue.name] = androidWav;
    console.log(`wrote ${androidWav} (${wav.length} bytes)`);
  }

  if (!haveFfmpeg()) {
    console.warn(
      '\n! ffmpeg not found — wrote WAV only. Point the native channels at the '
        + '.wav names, or install ffmpeg and re-run to get .ogg/.caf.',
    );
    return;
  }

  for (const cue of cues) {
    const wav = wavPaths[cue.name];
    const ogg = join(ANDROID_RAW, `${cue.name}.ogg`);
    ffmpeg(['-i', wav, '-c:a', 'libvorbis', '-q:a', '4', ogg]);
    console.log(`wrote ${ogg}`);
    const caf = join(IOS_SOUNDS, `${cue.ios}.caf`);
    ffmpeg(['-i', wav, '-f', 'caf', '-c:a', 'pcm_s16le', caf]);
    console.log(`wrote ${caf}`);
  }

  // The .wav files were an intermediate; keep only ogg/caf under version
  // control by removing the Android .wav (iOS never needs it). We leave the
  // removal to the caller's git add — the committed set is ogg + caf.
  console.log('\nGenerated ogg (Android) + caf (iOS). Commit those; the .wav '
    + 'files are intermediates.');
}

main();
