import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const listing = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { encoding: 'utf8' }));
const candidates = Object.entries(listing.devices)
  .filter(([runtime]) => runtime.includes('.iOS-'))
  .flatMap(([runtime, devices]) => devices.filter(device => device.isAvailable && device.name.startsWith('iPhone')).map(device => ({ ...device, runtime })));
const version = runtime => runtime.split('.iOS-')[1].split('-').map(Number);
candidates.sort((a, b) => {
  const seA = a.name.includes('SE (3rd generation)') ? 1 : 0;
  const seB = b.name.includes('SE (3rd generation)') ? 1 : 0;
  if (seA !== seB) return seB - seA;
  const av = version(a.runtime), bv = version(b.runtime);
  for (let i = 0; i < 3; i++) { if ((av[i] || 0) !== (bv[i] || 0)) return (bv[i] || 0) - (av[i] || 0); }
  return a.name.localeCompare(b.name);
});
const device = candidates[0];
if (!device) throw new Error('No available iPhone simulator.');
fs.mkdirSync('.build', { recursive: true });
fs.writeFileSync('.build/simulator-id.txt', device.udid + '\n');
fs.writeFileSync('.build/simulator-device.json', JSON.stringify(device, null, 2) + '\n');
console.log(`Test device: ${device.name} (${device.runtime})`);

