# Resonの解析API

自分のPCに音源を送り、AI解析と振動の編曲結果を取得するHTTP API。共通のクラウド推論サーバーや有料APIキーは使用しない。[PC環境の準備](PC-SERVER.md)、[OpenAPI 3.1仕様](api/openapi.json)、[クライアント](../pc-server/client.py)。

## 最短で試す

PCサーバーを起動した後、`haptic-lab/` または対応する配布ZIPのフォルダーから実行する。CLIの新規解析は `arranged` が標準。

```powershell
.\.pc-server\venv\Scripts\python.exe pc-server\client.py health
.\.pc-server\venv\Scripts\python.exe pc-server\client.py analyze --file HapticLab\Resources\MusicDemo.wav --output .build\demo-haptics.json
.\.pc-server\venv\Scripts\python.exe pc-server\client.py tracks
```

macOS / Linuxでは `.pc-server/venv/bin/python pc-server/client.py` と置き換える。

`health` は `protocolVersion: 1`、`apiVersion: "1.1.0"`、`trackVersions: [1,2,3]`、`arrangementAvailable` を返す。AI環境が未設定の場合、`arranged` は受け付けず旧方式へ自動で切り替えない。サンプルクライアントはPython標準ライブラリで動く。

指定曲で試す場合：

```powershell
.\.pc-server\venv\Scripts\python.exe pc-server\client.py analyze --video-id gNg2Qw5R-Q4 --output .build\serenade-haptics.json
.\.pc-server\venv\Scripts\python.exe pc-server\client.py export-ahap <trackID> --output .build\serenade-ahap
```

## 接続と認証

`arrangement-3.3`の`rhythmAgreement`と`downbeatAgreement`は、70 ms以内の一対一照合によるF1値。余分な拍と検出漏れを評価するモデル間の整合性指標で、正答率ではない。`rhythmDiagnostics`にはprecision/recall/F1と除去した拍時刻を保存する。各sectionの任意フィールド`groove`には、16分シャッフルの支持率・観測数と細分音符の分割位置を保存する。支持率は校正された正答確率ではない。旧スコアの読み込みは維持する。

PC自身では `http://127.0.0.1:8765`。別端末からはLANモードで起動し、`.pc-server/connection.json` のLAN URLを使う。全てのリクエストに `Authorization: Bearer <接続キー>` が必要。キーは `server-key.txt` と `connection.json` に保存する。これらはGitへ含めず、同じローカルネットワークで使う。

```powershell
$resonConnection = Get-Content .pc-server\connection.json -Raw | ConvertFrom-Json
$resonPort = ([uri]$resonConnection.addresses[0]).Port
$resonBase = 'http://127.0.0.1:' + $resonPort
$resonHeaders = @{ Authorization = 'Bearer ' + $resonConnection.token }
Invoke-RestMethod -Uri ($resonBase + '/health') -Headers $resonHeaders
$resonUploadHeaders = $resonHeaders.Clone()
$resonUploadHeaders['X-Generation-Style'] = 'arranged'
$resonJob = Invoke-RestMethod -Method Post -Uri ($resonBase + '/jobs/upload') -Headers $resonUploadHeaders -ContentType 'application/octet-stream' -InFile HapticLab\Resources\MusicDemo.wav
Invoke-RestMethod -Uri ($resonBase + '/jobs/' + $resonJob.id) -Headers $resonHeaders
```

最後のリクエストを約1秒間隔で繰り返す。状態は `queued` / `running` / `done` / `failed` / `canceled`。`done` の `track` が結果。HTTP 200でも `state: "failed"` の場合があるため、状態と `message` を確認する。

## エンドポイント

| メソッド・パス | 内容 |
| --- | --- |
| `GET /health` | 互換性、YouTube取得ツールとAI環境の可用性 |
| `GET /openapi.json` | 認証付きのOpenAPI仕様 |
| `POST /jobs` | YouTube動画IDから解析ジョブを作成 |
| `POST /jobs/upload` | 音声・動画の生バイト列から解析ジョブを作成 |
| `GET /jobs/{jobID}` | 状態・進捗・完成した振動 |
| `DELETE /jobs/{jobID}` | キャンセル |
| `GET /tracks` | 保存一覧 |
| `GET /tracks/{trackID}` | 振動JSONを取得 |
| `GET /tracks/{trackID}/ahap` | `{manifest, files}` 形式のAHAP JSONバンドル |
| `DELETE /tracks/{trackID}` | 対応する振動・スコア・グラフ・AHAPを削除 |
| `POST /shutdown` | 停止。保存した振動は保持 |

YouTubeジョブのJSON：

```json
{"videoID":"gNg2Qw5R-Q4","title":"natori - Serenade","style":"arranged","profile":"standard"}
```

`videoID` は11文字のID。`style` は `arranged`（AI編曲）、`following`（旧音追従）、`musical`（旧リズム中心）。HTTPとPythonのライブラリ関数で `style` を省略した場合は旧クライアント互換のため `following`。新しいCLIとiPhoneは `arranged` を明示する。`profile` は `standard` / `orchestral`。後者は疎な自然のアタックを優先する。

アップロードはmultipartではなく生バイト列で、`Content-Length` が必要。chunked送信は未対応。

| ヘッダー | 値 |
| --- | --- |
| `Content-Type` | `application/octet-stream` |
| `X-Media-Title` | 曲名UTF-8のBase64 |
| `X-Generation-Style` | `arranged` / `following` / `musical` |
| `X-Music-Profile` | `standard` / `orchestral` |

YouTubeはyt-dlpで取得する。動画の制限やサービスの仕様変更で失敗する場合がある。`POST /jobs` と `POST /jobs/upload` は毎回取得・解析・編曲を実行し、保存済みの結果を再利用しない。同一音源・モデル・設定でも、新しい結果IDで保存する。保存結果の再取得は `GET /tracks/{trackID}` を使う。

## 結果とAHAP

`arranged` の結果は振動データ **version 3**。旧方式はversion 2。HTTP互換性の `protocolVersion` は1を維持する。

- `duration` / `time` は秒。`envelope.intensity` が編曲済みの持続強度、`taps` が独立したアクセント。強度・イベントの鋭さは0〜1。
- `arrangement.sections` はAIの区間推定とモチーフ系統、`bars` は小節ごとの選択、`rhythmSource` / `rhythmAgreement` / `downbeatAgreement` は拍の採用根拠。
- `confidence` はモデル出力の平均値で、実際の正答率ではない。CLAPは音の雰囲気の比較で、歌詞や意図の解釈はしない。
- `spectrum` は20 Hz〜8 kHzの参考周波数表示で、振動生成の根拠とは別。
- `analysis.serverTrackID` を保存結果とAHAPの取得に使う。モデル・設定・音声SHA-256とジョブIDで結果ごとのIDを作る。前の結果を上書きせず、個別に取得・削除できる。

AHAPは8秒以下のクリップへ分け、持続用とアクセント用を別プレーヤーへ載せて同時開始する。manifestは各クリップの開始時刻とファイル名を持つ。持続の制御曲線をアクセントへ掛けないために分けている。音楽の音声ファイルは含まない。[詳細](AHAP.md)。旧方式の保存データにはAHAPがなく、その取得は404になる。

結果JSONを取得してもiPhoneの振動は自動では発生しない。Reson等のCore Hapticsを扱う実機アプリで再生する。

## 制限と保存

- 1曲20分以内、1ファイル512 MiB以内（536,870,912バイト）。
- 未完了ジョブは最大8件、処理は1件ずつ。
- `jobID` はサーバー再起動で失効。保存した `trackID` は保持。
- 一時音源、分離音源、スペクトログラムは成功・失敗・キャンセル時に削除。
- `.pc-server/data/tracks/` に振動・解析グラフ・スコア、`data/exports/` にAHAPを保存。
- HTTP 400は入力・上限・AI未設定、401は認証または接続元、404は対象なし、500は内部の失敗。
- CORSは用意していない。Python等のHTTPクライアントを使う。

相談時はOS、実行コマンド、接続キーを除いたエラーとジョブ状態を伝える。
