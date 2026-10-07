param(
    [switch]$Watch,
    [string]$ConnectionFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.pc-server/connection.json')
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$connection = Get-Content -LiteralPath $ConnectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
$port = ([uri]$connection.addresses[0]).Port
$baseURL = 'http://127.0.0.1:' + $port
$headers = @{Authorization = ('Bearer ' + $connection.token)}
$null = Invoke-RestMethod -Uri ($baseURL + '/health') -Headers $headers -TimeoutSec 3

Write-Host ''
Write-Host '========== iPhoneの接続設定 ==========' -ForegroundColor Cyan
$lanAddresses = @($connection.addresses | Where-Object { ([uri]$_).Host -ne '127.0.0.1' })
if ($lanAddresses.Count -eq 0) {
    Write-Host 'この接続URLはPC専用です。iPhoneから使う場合はLANモードで起動してください。'
}
foreach ($address in $connection.addresses) { Write-Host ('HTTP URL: ' + $address) }
Write-Host ('接続キー: ' + $connection.token) -ForegroundColor Yellow
Write-Host 'iPhoneの「解析方法・PCサーバー」へURLと接続キーを入力してください。'
Write-Host ''
if (!$Watch) { return }

Write-Host '解析の進捗を表示します。iPhoneから曲の解析を開始してください。'
Write-Host '進捗率は処理段階の目安です。推論中は数値が変わらない場合があります。'
Write-Host 'このウィンドウを閉じてもサーバーと解析は続きます。'
Write-Host 'Ctrl+Cで進捗表示を終了できます。サーバーの停止はStop-PCServer.ps1です。'
Write-Host ''
$workingRoot = Join-Path (Split-Path -Parent $ConnectionFile) 'data/working'
$initialJobs = @{}
foreach ($folder in @(Get-ChildItem -LiteralPath $workingRoot -Directory -ErrorAction SilentlyContinue)) {
    $initialJobs[$folder.Name] = $true
}
$finished = @{}
$lastDisplay = @{}
$titles = @{}
$nextHealthCheck = [datetime]::MinValue
$healthFailures = 0

while ($true) {
    if ([datetime]::UtcNow -ge $nextHealthCheck) {
        try {
            $null = Invoke-RestMethod -Uri ($baseURL + '/health') -Headers $headers -TimeoutSec 3
            $healthFailures = 0
        } catch {
            $healthFailures++
            if ($healthFailures -ge 3) {
                Write-Host 'サーバーへの接続が切れました。進捗表示を終了します。' -ForegroundColor Yellow
                return
            }
        }
        $nextHealthCheck = [datetime]::UtcNow.AddSeconds(5)
    }
    foreach ($folder in @(Get-ChildItem -LiteralPath $workingRoot -Directory -ErrorAction SilentlyContinue)) {
        $jobID = $folder.Name
        if ($jobID -notmatch '^[0-9a-f-]{36}$' -or $finished.ContainsKey($jobID)) { continue }
        try {
            # Ask the running server so canceled/crashed jobs and old sessions are handled correctly.
            $status = Invoke-RestMethod -Uri ($baseURL + '/jobs/' + $jobID) -Headers $headers -TimeoutSec 3
        } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
                $finished[$jobID] = $true
            }
            continue
        }
        $terminal = $status.state -in @('done', 'failed', 'canceled')
        if ($terminal) { $finished[$jobID] = $true }
        # Opening the monitor should not replay the history of completed analyses.
        if ($terminal -and $initialJobs.ContainsKey($jobID) -and !$lastDisplay.ContainsKey($jobID)) { continue }
        if (!$titles.ContainsKey($jobID)) {
            try {
                $request = Get-Content -LiteralPath (Join-Path $folder.FullName 'request.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $titles[$jobID] = [string]$request.title
            } catch { $titles[$jobID] = $jobID.Substring(0, 8) }
        }
        $percent = [int][math]::Round([math]::Min(1.0, [math]::Max(0.0, [double]$status.progress)) * 100)
        $label = switch ($status.state) {
            'queued' { '解析待ち' }
            'running' { '解析中' }
            'done' { '完了' }
            'failed' { '失敗' }
            'canceled' { 'キャンセル' }
            default { [string]$status.state }
        }
        $text = '{0} [{1}] {2} {3}% — {4}' -f $titles[$jobID], $jobID.Substring(0, 8), $label, $percent, $status.message
        $previous = $lastDisplay[$jobID]
        $now = [datetime]::UtcNow
        if (!$previous -or $previous.text -ne $text -or $now -ge $previous.at.AddSeconds(15)) {
            $color = if ($status.state -eq 'failed') { 'Red' } elseif ($status.state -eq 'done') { 'Green' } else { 'Gray' }
            Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $text) -ForegroundColor $color
            $lastDisplay[$jobID] = @{text = $text; at = $now}
        }
    }
    Start-Sleep -Seconds 1
}
