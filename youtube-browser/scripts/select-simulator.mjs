import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const requestedVersion = process.env.RESON_WEB_SIMULATOR_OS
  || execFileSync('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-version'], { encoding: 'utf8' }).trim();
const runtimeSuffix = `.iOS-${requestedVersion.replaceAll('.', '-')}`;
const listing = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { encoding: 'utf8' }));
const candidates = Object.entries(listing.devices)
  .filter(([runtime]) => runtime.endsWith(runtimeSuffix))
  .flatMap(([runtime, devices]) => devices
    .filter(device => device.isAvailable && device.name.startsWith('iPhone'))
    .map(device => ({ ...device, runtime })));
candidates.sort((a, b) => {
  const seA = a.name.includes('SE (3rd generation)') ? 1 : 0;
  const seB = b.name.includes('SE (3rd generation)') ? 1 : 0;
  return seB - seA || a.name.localeCompare(b.name);
});
const device = candidates[0];
if (!device) throw new Error(`No available iPhone simulator for iOS ${requestedVersion}. Available runtimes: ${Object.keys(listing.devices).join(', ')}`);
fs.mkdirSync('.build', { recursive: true });
fs.writeFileSync('.build/simulator-id.txt', device.udid + '\n');
fs.writeFileSync('.build/simulator-device.json', JSON.stringify(device, null, 2) + '\n');
console.log(`Test device: ${device.name} (${device.runtime}); SDK-compatible iOS ${requestedVersion}`);
