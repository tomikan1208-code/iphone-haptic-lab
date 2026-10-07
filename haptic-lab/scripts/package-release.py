"""Package the verified iPhone IPA and an explicit allowlist of onboarding files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DOCS = ['INSTALL.md', 'INSTALL-WINDOWS.md', 'BUILD.md', 'AI-INSTALL.md', 'AHAP.md',
        'API.md', 'PC-SERVER.md', 'GOOGLE-LOGIN.md', 'MUSIC.md', 'HAPTIC-ARRANGEMENT-DESIGN.md',
        'verification/SERENADE.md', 'verification/SUB-FRAME-SECTIONS.md', 'verification/serenade-metrics.json',
        'verification/serenade-arrangement.png', 'verification/serenade-56s-bed.ahap',
        'verification/serenade-56s-accents.ahap',
        'verification/SERENADE-REFERENCE.md', 'verification/serenade-reference.json',
        'verification/SERENADE-IMPROVED.md',
        'verification/arrangement-3.3/serenade-metrics.json',
        'verification/arrangement-3.3/serenade-rhythm-checks.json',
        'verification/arrangement-3.3/serenade-arrangement.png',
        'verification/arrangement-3.3/serenade-56s-bed.ahap',
        'verification/arrangement-3.3/serenade-56s-accents.ahap']
COMPANION = ['server.py', 'worker.py', 'signal_analysis.py', 'client.py',
             'music_ai.py', 'music_rhythm.py', 'haptic_arrangement.py', 'check-ml.py', 'setup-ml.ps1', 'setup-ml.sh',
             'requirements-ml.txt', 'requirements.txt', 'Start-PCServer.ps1', 'Show-PCServer.ps1', 'Stop-PCServer.ps1', 'start.sh']


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def package(output, source_commit=None):
    output = Path(output).resolve()
    ipa = output / 'HapticLab-unsigned.ipa'
    with zipfile.ZipFile(ipa) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError('IPA ZIP integrity failed: ' + bad)
        plist = plistlib.loads(archive.read('Payload/HapticLab.app/Info.plist'))
        if plist.get('CFBundleDisplayName') != 'Reson' or plist.get('MinimumOSVersion') != '16.0':
            raise ValueError('Expected a Reson IPA targeting iOS 16.0.')
        if any(name.startswith('Payload/HapticLab.app/_CodeSignature/') for name in archive.namelist()):
            raise ValueError('This distribution expects an unsigned IPA.')
    version = plist['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid app version.')
    summary_path = ROOT / '.build/test-summary.json'
    summary = json.loads(summary_path.read_text(encoding='utf-8-sig'))
    if summary.get('result') != 'Passed' or summary.get('failedTests') != 0 or not summary.get('passedTests'):
        raise ValueError('Native tests must pass before packaging.')
    commit = source_commit or os.environ.get('GITHUB_SHA')
    if not commit or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Set GITHUB_SHA or pass --source-commit with the verified source commit.')
    repository = os.environ.get('GITHUB_REPOSITORY', 'tomikan1208-code/iphone-haptic-lab')
    run_id = os.environ.get('GITHUB_RUN_ID')
    info = dict(displayName='Reson', version=version, build=plist['CFBundleVersion'],
                bundleIdentifier=plist['CFBundleIdentifier'], minimumOSVersion=plist['MinimumOSVersion'],
                signed=False, sourceCommit=commit, repository=repository,
                ipaSHA256=digest(ipa), apiVersion='1.1.0', protocolVersion=1,
                nativeTestsPassed=summary['passedTests'], nativeTestsFailed=0,
                physicalHapticsTested=False)
    if run_id:
        info['workflowURL'] = f'https://github.com/{repository}/actions/runs/{run_id}'
    (output / 'BUILD-INFO.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output / 'TEST-SUMMARY.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    files = {
        'HapticLab-unsigned.ipa': ipa,
        'BUILD-INFO.json': output / 'BUILD-INFO.json',
        'TEST-SUMMARY.json': output / 'TEST-SUMMARY.json',
        'README.md': ROOT / 'README.md',
        'Start-PCServer.bat': ROOT / 'Start-PCServer.bat',
        'llms.txt': ROOT / 'llms.txt',
        'docs/api/openapi.json': ROOT / 'docs/api/openapi.json',
        'HapticLab/Resources/MusicDemo.wav': ROOT / 'HapticLab/Resources/MusicDemo.wav'
    }
    files.update({f'docs/{name}': ROOT / 'docs' / name for name in DOCS})
    files.update({f'pc-server/{name}': ROOT / 'pc-server' / name for name in COMPANION})
    for path in files.values():
        if not path.is_file():
            raise FileNotFoundError(path)
    bundle = output / 'Reson-install.zip'
    with zipfile.ZipFile(bundle, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('START-HERE.txt',
                         'Reson: YouTube videos with synchronized iPhone haptics.\n'
                         'Open docs/INSTALL.md for installation or docs/AI-INSTALL.md for an AI prompt.\n'
                         'Sign HapticLab-unsigned.ipa locally with your own Apple Account.\n'
                         'Music AI preparation on PC: docs/PC-SERVER.md. API: docs/API.md.\n')
        archive.writestr('SHA256SUMS.txt', f"{info['ipaSHA256']}  HapticLab-unsigned.ipa\n")
        for name, path in sorted(files.items()):
            archive.write(path, name)
    with zipfile.ZipFile(bundle) as archive:
        if archive.testzip():
            raise ValueError('Install bundle ZIP integrity failed.')
        if set(archive.namelist()) != set(files) | {'START-HERE.txt', 'SHA256SUMS.txt'}:
            raise ValueError('Unexpected file in installation bundle.')
    for name in DOCS:
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'docs' / name, destination)
    shutil.copyfile(ROOT / 'llms.txt', output / 'llms.txt')
    assets = [ipa, bundle, output / 'BUILD-INFO.json', output / 'TEST-SUMMARY.json']
    (output / 'SHA256SUMS.txt').write_text(''.join(f'{digest(path)}  {path.name}\n' for path in assets), encoding='utf-8')
    print(json.dumps(dict(version=version, bundle=str(bundle), files=len(files), ipaSHA256=info['ipaSHA256']), ensure_ascii=False))
    return info


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/artifact')
    parser.add_argument('--source-commit')
    args = parser.parse_args()
    package(args.output, args.source_commit)
