param()
$ErrorActionPreference = 'Stop'
$playerRoot = Split-Path -Parent $PSScriptRoot
$privateRoot = Join-Path $playerRoot '.pc-server'
$pidFile = Join-Path $privateRoot 'server.pid'
if (!(Test-Path -LiteralPath $pidFile)) { Write-Output 'PC server is not running.'; exit 0 }
$savedPid = [int](Get-Content -LiteralPath $pidFile)
$runningServer = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
$serverScript = Join-Path $PSScriptRoot 'server.py'
if (!$runningServer) { Remove-Item -LiteralPath $pidFile; Write-Output 'PC server is stopped.'; exit 0 }
if (!$runningServer.CommandLine -or !$runningServer.CommandLine.Contains($serverScript)) {
    throw 'Saved PID belongs to another process. No process was stopped.'
}
$connection = Get-Content -LiteralPath (Join-Path $privateRoot 'connection.json') -Raw | ConvertFrom-Json
$port = ([uri]$connection.addresses[0]).Port
$null = Invoke-RestMethod -Method Post -Uri ('http://127.0.0.1:' + $port + '/shutdown') `
    -Headers @{Authorization = ('Bearer ' + $connection.token)} -TimeoutSec 5
Wait-Process -Id $savedPid -Timeout 15 -ErrorAction SilentlyContinue
if (Get-Process -Id $savedPid -ErrorAction SilentlyContinue) { throw 'Server is still stopping; check server-error.log.' }
Remove-Item -LiteralPath $pidFile
Write-Output 'PC server stopped. Saved haptic tracks are kept.'
