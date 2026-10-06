import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const assets = path.join(root, 'HapticLab', 'Resources', 'Assets.xcassets');
const iconDir = path.join(assets, 'AppIcon.appiconset');
fs.mkdirSync(iconDir, { recursive: true });
fs.mkdirSync(path.join(assets, 'AccentColor.colorset'), { recursive: true });
const contents = { info: { author: 'xcode', version: 1 } };
fs.writeFileSync(path.join(assets, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');
fs.writeFileSync(path.join(assets, 'AccentColor.colorset', 'Contents.json'), JSON.stringify({
  colors: [{ idiom: 'universal', color: { 'color-space': 'srgb', components: { red: '0.118', green: '0.843', blue: '0.376', alpha: '1.000' } } }], ...contents
}, null, 2) + '\n');

const crcTable = Array.from({ length: 256 }, (_, n) => {
  for (let k = 0; k < 8; k++) n = (n & 1) ? (0xedb88320 ^ (n >>> 1)) : (n >>> 1);
  return n >>> 0;
});
function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const name = Buffer.from(type);
  const header = Buffer.alloc(4); header.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([header, name, data, crc]);
}
function icon(size) {
  const pixels = Buffer.alloc((size * 3 + 1) * size);
  const mix = (base, color, alpha) => base.map((value, index) => value * (1 - alpha) + color[index] * alpha);
  for (let y = 0; y < size; y++) {
    const offset = y * (size * 3 + 1);
    for (let x = 0; x < size; x++) {
      const px = (x + 0.5) * 1024 / size;
      const py = (y + 0.5) * 1024 / size;
      const radial = Math.max(0, 1 - Math.hypot(px - 750, py - 260) / 900);
      let rgb = [8 + radial * 5, 10 + radial * 16, 9 + radial * 7];
      const t = (px - 175) / 674;
      if (t >= 0 && t <= 1) {
        const wave = 512 - Math.sin(t * Math.PI * 8) * 145 * Math.sin(t * Math.PI);
        const slope = -(Math.PI * 8 * Math.cos(t * Math.PI * 8) * Math.sin(t * Math.PI) + Math.sin(t * Math.PI * 8) * Math.PI * Math.cos(t * Math.PI)) * 145 / 674;
        const distance = Math.abs(py - wave) / Math.sqrt(1 + slope * slope);
        rgb = mix(rgb, [30, 215, 96], 0.20 * Math.exp(-distance * distance / 850));
        rgb = mix(rgb, [30, 215, 96], Math.max(0, Math.min(1, (11 - distance) * size / 1024)));
      }
      for (let index = 0; index < 3; index++) pixels[offset + 1 + x * 3 + index] = Math.round(rgb[index]);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}
const images = [];
for (const points of [20, 29, 40, 60]) {
  for (const scale of [2, 3]) {
    const filename = `icon-${points}@${scale}x.png`;
    fs.writeFileSync(path.join(iconDir, filename), icon(points * scale));
    images.push({ idiom: 'iphone', size: `${points}x${points}`, scale: `${scale}x`, filename });
  }
}
fs.writeFileSync(path.join(iconDir, 'icon-1024.png'), icon(1024));
images.push({ idiom: 'ios-marketing', size: '1024x1024', scale: '1x', filename: 'icon-1024.png' });
fs.writeFileSync(path.join(iconDir, 'Contents.json'), JSON.stringify({ images, ...contents }, null, 2) + '\n');
console.log('Generated opaque iPhone app icons and accent color.');
