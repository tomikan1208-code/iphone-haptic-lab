param([switch]$CPU)
$ErrorActionPreference = 'Stop'
$arrangementRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $arrangementRoot
if (!(Get-Command uv -ErrorAction SilentlyContinue)) {
    throw 'uvが必要です。winget install --id astral-sh.uv -e を実行してください。'
}
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'モデル推論コードの取得にGitが必要です。winget install --id Git.Git -e を実行してください。'
}
$arrangementPython = Join-Path $arrangementRoot '.pc-server/ml-venv/Scripts/python.exe'
if (!(Test-Path -LiteralPath $arrangementPython)) {
    uv venv '.pc-server/ml-venv' --python 3.11
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.11環境を作成できませんでした。' }
}
$torchIndex = if ($CPU) { 'https://download.pytorch.org/whl/cpu' } else { 'https://download.pytorch.org/whl/cu124' }
uv pip install --python $arrangementPython torch==2.5.1 torchaudio==2.5.1 --index-url $torchIndex
if ($LASTEXITCODE -ne 0) { throw 'PyTorchを導入できませんでした。' }
uv pip install --python $arrangementPython -r 'pc-server/requirements-ml.txt' --extra-index-url $torchIndex --index-strategy unsafe-best-match
if ($LASTEXITCODE -ne 0) { throw '音楽AIの依存関係を導入できませんでした。' }
& $arrangementPython 'pc-server/check-ml.py'
if ($LASTEXITCODE -ne 0) { throw '音楽AIの動作確認に失敗しました。' }
Write-Output 'AI編曲の準備ができました。モデルは初回解析時に取得し、以降はこのPCのキャッシュを使います。'
