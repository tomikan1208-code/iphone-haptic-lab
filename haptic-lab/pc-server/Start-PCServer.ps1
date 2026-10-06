param([switch]$Lan, [ValidateRange(1,65535)][int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$playerRoot = Split-Path -Parent $PSScriptRoot
$privateRoot = Join-Path $playerRoot '.pc-server'
$pythonPath = Join-Path $privateRoot 'venv/Scripts/python.exe'
Set-Location -LiteralPath $playerRoot
if (!(Get-Command uv -ErrorAction SilentlyContinue)) {
    throw 'uvが必要です。winget install --id astral-sh.uv -e を実行し、PowerShellを開き直してください。'
}
$serverScript = Join-Path $PSScriptRoot 'server.py'
$pidFile = Join-Path $privateRoot 'server.pid'
if (Test-Path -LiteralPath $pidFile) {
    $savedPid = [int](Get-Content -LiteralPath $pidFile)
    $runningServer = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
    if ($runningServer -and $runningServer.CommandLine -and $runningServer.CommandLine.Contains($serverScript)) {
        $savedConnection = Get-Content -LiteralPath (Join-Path $privateRoot 'connection.json') -Raw | ConvertFrom-Json
        if (([uri]$savedConnection.addresses[0]).Port -ne $Port -or
            ($Lan -and @($savedConnection.addresses | Where-Object { ([uri]$_).Host -ne '127.0.0.1' }).Count -eq 0)) {
            throw '起動中のサーバーは接続設定が異なります。Stop-PCServer.ps1で停止してから起動し直してください。'
        }
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
$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) { throw ('起動に失敗しました。' + (Join-Path $privateRoot 'server-error.log') + 'を確認してください。') }
    $connectionFile = Join-Path $privateRoot 'connection.json'
    if (!(Test-Path -LiteralPath $connectionFile)) { continue }
    try {
        $connection = Get-Content -LiteralPath $connectionFile -Raw | ConvertFrom-Json
        $health = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $Port + '/health') `
            -Headers @{Authorization = ('Bearer ' + $connection.token)} -TimeoutSec 1
        if ($health.protocolVersion -eq 1) { $ready = $true; break }
    } catch { }
}
if (!$ready) { throw ('サーバーの応答を確認できません。' + (Join-Path $privateRoot 'server-error.log') + 'を確認してください。') }
Set-Content -LiteralPath $pidFile -Value $process.Id
Write-Output ('PCサーバーを起動しました。接続先・接続キー: ' + (Join-Path $privateRoot 'connection.json'))
Write-Output ('接続先: ' + ($connection.addresses -join ', '))
Write-Output ('API仕様: http://127.0.0.1:' + $Port + '/openapi.json (接続キーが必要)')
