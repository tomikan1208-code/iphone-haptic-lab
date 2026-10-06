import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Original, deterministic sound; no downloaded audio or third-party samples.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sampleRate = 22050, duration = 12, samples = sampleRate * duration;
const wav = Buffer.alloc(44 + samples * 2);
wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(sampleRate, 24); wav.writeUInt32LE(sampleRate * 2, 28);
wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36);
wav.writeUInt32LE(samples * 2, 40);
let noiseState = 123456789;
for (let i = 0; i < samples; i++) {
  const time = i / sampleRate;
  const phase = Math.max(0, time - 0.2);
  const beat = phase % 0.5, eighth = phase % 0.25;
  const frequency = [55, 65.406, 73.416, 82.407][Math.floor(phase / 2) % 4];
  const bass = Math.sin(2 * Math.PI * frequency * phase) * 0.19 * Math.exp(-beat * 4);
  const kick = Math.sin(2 * Math.PI * (65 * beat + 65 * (1 - Math.exp(-beat * 35)) / 35)) * 0.45 * Math.exp(-beat * 27);
  noiseState = (Math.imul(noiseState, 1664525) + 1013904223) >>> 0;
  const hat = (noiseState / 0xffffffff * 2 - 1) * Math.exp(-eighth * 140) * 0.10;
  const bell = Math.sin(2 * Math.PI * frequency * 8 * phase) * 0.06 * Math.exp(-eighth * 12);
  const fade = time < 0.2 || time >= 11.5 ? 0 : Math.min(1, (time - 0.2) * 80, (11.5 - time) * 8);
  wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, (bass + kick + hat + bell) * fade)) * 32767), 44 + i * 2);
}
fs.writeFileSync(path.join(root, 'HapticLab', 'Resources', 'MusicDemo.wav'), wav);
console.log(`Generated original music demo: ${duration}s, mono PCM, ${wav.length} bytes.`);
