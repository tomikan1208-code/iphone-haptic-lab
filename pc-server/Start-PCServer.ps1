param([switch]$Lan, [ValidateRange(1,65535)][int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$playerRoot = Split-Path -Parent $PSScriptRoot
$privateRoot = Join-Path $playerRoot '.pc-server'
$pythonPath = Join-Path $privateRoot 'venv/Scripts/python.exe'
Set-Location -LiteralPath $playerRoot
$serverScript = Join-Path $PSScriptRoot 'server.py'
$pidFile = Join-Path $privateRoot 'server.pid'
if (Test-Path -LiteralPath $pidFile) {
    $savedPid = [int](Get-Content -LiteralPath $pidFile)
    $runningServer = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
    if ($runningServer -and $runningServer.CommandLine -and $runningServer.CommandLine.Contains($serverScript)) {
        Write-Output ('PCサーバーは起動済みです。接続設定: ' + (Join-Path $privateRoot 'connection.json'))
        exit 0
    }
}
if (!(Test-Path -LiteralPath $pythonPath)) {
    uv --cache-dir '.build/uv-cache' venv '.pc-server/venv' --python 3.13
    if ($LASTEXITCODE -ne 0) { throw 'Python環境を作成できませんでした。uvをインストールしてください。' }
}
uv pip install --python $pythonPath --cache-dir '.build/uv-cache' -r 'pc-server/requirements.txt'
if ($LASTEXITCODE -ne 0) { throw '依存ライブラリの導入に失敗しました。' }
$listenHost = if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }
$arguments = @(('"' + $serverScript + '"'), '--host', $listenHost, '--port', $Port)
$process = Start-Process -FilePath $pythonPath -ArgumentList $arguments -WorkingDirectory $playerRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $privateRoot 'server.log') -RedirectStandardError (Join-Path $privateRoot 'server-error.log')
Start-Sleep -Seconds 1
$process.Refresh()
if ($process.HasExited) { throw ('起動に失敗しました。' + (Join-Path $privateRoot 'server-error.log') + 'を確認してください。') }
Set-Content -LiteralPath $pidFile -Value $process.Id
Write-Output ('PCサーバーを起動しました。接続先・接続キー: ' + (Join-Path $privateRoot 'connection.json'))
