import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const patterns = JSON.parse(read('HapticLab/Resources/Presets.json'));
assert.equal(patterns.length, 10);
assert.equal(new Set(patterns.map(pattern => pattern.id)).size, patterns.length);
let events = 0;
for (const pattern of patterns) {
  assert(pattern.duration > 0 && pattern.duration <= 30, `${pattern.id}: duration`);
  assert(pattern.events.length > 0 && pattern.events.length <= 256, `${pattern.id}: events`);
  for (const event of pattern.events) {
    assert(['tap', 'continuous'].includes(event.kind), `${pattern.id}: kind`);
    assert(event.time >= 0 && event.time <= pattern.duration, `${pattern.id}: time`);
    assert(event.intensity >= 0 && event.intensity <= 1, `${pattern.id}: intensity`);
    assert(event.sharpness >= 0 && event.sharpness <= 1, `${pattern.id}: sharpness`);
    if (event.kind === 'continuous') {
      assert(event.duration > 0 && event.duration <= 30 && event.time + event.duration <= pattern.duration, `${pattern.id}: continuous duration`);
    } else assert.equal(event.duration, 0);
    events++;
  }
  for (const curve of pattern.curves) {
    assert(['intensity', 'sharpness'].includes(curve.parameter));
    assert(curve.points.length >= 2 && curve.points.length <= 16);
    let previous = -Infinity;
    for (const point of curve.points) {
      assert(point.time > previous && point.time >= 0 && point.time <= pattern.duration);
      assert(point.value >= 0 && point.value <= 1);
      previous = point.time;
    }
  }
}
const project = read('HapticLab.xcodeproj/project.pbxproj');
for (const file of fs.readdirSync(path.join(root, 'HapticLab')).filter(file => file.endsWith('.swift'))) {
  assert(project.includes(`path = ${file};`), `${file} is missing from the Xcode project`);
}
assert(project.includes('IPHONEOS_DEPLOYMENT_TARGET = 16.0;'));
assert(project.includes('TEST_TARGET_NAME = HapticLab;'));
const icons = JSON.parse(read('HapticLab/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json'));
for (const icon of icons.images) {
  const data = fs.readFileSync(path.join(root, 'HapticLab/Resources/Assets.xcassets/AppIcon.appiconset', icon.filename));
  assert.equal(data.subarray(1, 4).toString(), 'PNG');
  const pixels = Number(icon.size.split('x')[0]) * Number(icon.scale.replace('x', ''));
  assert.equal(data.readUInt32BE(16), pixels);
  assert.equal(data.readUInt32BE(20), pixels);
}
console.log(`Project checks passed: ${patterns.length} patterns, ${events} events, ${icons.images.length} app icons.`);

