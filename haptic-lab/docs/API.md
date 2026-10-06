# Resonの解析API

ResonはYouTube動画を振動付きで再生するiPhoneアプリです。ここでは、追加機能のPC解析を自分のプログラムやAIから利用する方法を説明します。iPhoneだけで使う場合、APIの設定は不要です。

APIは利用者のPCで動きます。共通のクラウドAPI・有料APIキー・開発者のサーバーへの接続はありません。Google OAuth、YouTube Data API、Appleの署名は別の設定です。

## 最短で試す

[PCサーバーの手順](PC-SERVER.md)でサーバーを起動してください。以下は `haptic-lab/`、または `Reson-install.zip` を展開したフォルダーから実行します。YouTubeの状況に左右されないよう、最初は同梱の12秒音源を使います。

Windows PowerShell:

```powershell
.\.pc-server\venv\Scripts\python.exe pc-server\client.py health
.\.pc-server\venv\Scripts\python.exe pc-server\client.py analyze --file HapticLab\Resources\MusicDemo.wav --output .build\demo-haptics.json
.\.pc-server\venv\Scripts\python.exe pc-server\client.py tracks
```

macOS / Linux（サーバーを起動したまま、別のターミナルで）:

```sh
.pc-server/venv/bin/python pc-server/client.py health
.pc-server/venv/bin/python pc-server/client.py analyze --file HapticLab/Resources/MusicDemo.wav --output .build/demo-haptics.json
.pc-server/venv/bin/python pc-server/client.py tracks
```

`health` は `protocolVersion: 1`、`apiVersion: "1.0.0"` を返します。解析はジョブの作成・進捗確認・結果取得まで自動で行い、約12秒の振動データをJSONへ保存します。サンプルクライアントはPython標準ライブラリだけで動きます。

## 接続と認証

標準のURLはPC自身なら `http://127.0.0.1:8765`。iPhoneや別のPCなら、`-Lan` / `--lan` で起動し、`.pc-server/connection.json` の `addresses` にある `http://192.168.…:8765` 等を使います。iPhoneの `127.0.0.1` はiPhone自身を指します。

すべてのリクエストに `Authorization: Bearer <接続キー>` が必要です。接続キーは初回起動時に生成され、`.pc-server/server-key.txt` に保持します。`connection.json`、接続キー、ログ、音源、キャッシュはGitに含めません。APIは同じローカルネットワークで利用してください。

PowerShellでHTTPを直接呼ぶ例（キーはローカルファイルから読み込みます）:

```powershell
$resonConnection = Get-Content .pc-server\connection.json -Raw | ConvertFrom-Json
$resonPort = ([uri]$resonConnection.addresses[0]).Port
$resonBase = 'http://127.0.0.1:' + $resonPort
$resonHeaders = @{ Authorization = 'Bearer ' + $resonConnection.token }
Invoke-RestMethod -Uri ($resonBase + '/health') -Headers $resonHeaders
$resonJob = Invoke-RestMethod -Method Post -Uri ($resonBase + '/jobs/upload') -Headers $resonHeaders -ContentType 'application/octet-stream' -InFile HapticLab\Resources\MusicDemo.wav
Invoke-RestMethod -Uri ($resonBase + '/jobs/' + $resonJob.id) -Headers $resonHeaders
```

最後のリクエストを約1秒間隔で繰り返し、`state` が `done` になったら `track` を取得します。処理中は `queued` / `running`、終了時は `done` / `failed` / `canceled` です。解析の失敗はHTTP 200でも `state: "failed"` として返るので、状態と `message` を確認してください。

## エンドポイント

| メソッド・パス | 内容 |
| --- | --- |
| `GET /health` | 接続、互換性、YouTube取得ツールの有無 |
| `GET /openapi.json` | 起動中のAPIのOpenAPI 3.1仕様（認証が必要） |
| `POST /jobs` | YouTube動画IDから解析ジョブを作成 |
| `POST /jobs/upload` | 音声・動画のバイト列を送って解析ジョブを作成 |
| `GET /jobs/{jobID}` | 状態・進捗・完成した振動データ |
| `DELETE /jobs/{jobID}` | 解析をキャンセル |
| `GET /tracks` | PCに保存した振動の一覧 |
| `GET /tracks/{trackID}` | 保存した振動データを取得 |
| `DELETE /tracks/{trackID}` | PCの保存データを1曲削除 |
| `POST /shutdown` | サーバー停止。保存した振動は保持 |

AIやクライアント生成ツールには、リポジトリにある [openapi.json](api/openapi.json) を渡せます。認証なしで読める静的ファイルと、起動中サーバーの仕様は同じ内容です。[サンプルのコード](../pc-server/client.py)も参照してください。

`POST /jobs` のJSON:

```json
{"videoID":"BaW_jenozKc","title":"試験動画","style":"following","profile":"standard"}
```

`videoID` はURLではなく11文字のIDです。`style` は `following`（音に追従、標準）か `musical`（リズム中心）、`profile` は `standard`（標準）か `orchestral`（オーケストラ向け）です。`orchestral` は自然な打音を優先し、リズム中心の固定拍の追加より優先されます。YouTubeの取得はyt-dlpを使うため、制限や仕様変更で失敗する場合があります。

`POST /jobs/upload` はmultipartではなくファイルの生バイト列です。`Content-Length` が必要で、chunked送信には対応していません。必要に応じて次のヘッダーを付けます。

| ヘッダー | 値 |
| --- | --- |
| `Content-Type` | `application/octet-stream` |
| `X-Media-Title` | 曲名のUTF-8をBase64へ変換した文字列 |
| `X-Generation-Style` | `following` / `musical` |
| `X-Music-Profile` | `standard` / `orchestral` |

## 結果と制限

結果の `version` は振動データ形式の **2**、HTTP互換性の `protocolVersion` は **1** です。`duration` と各 `time` は秒、振動の強さ・鋭さ・帯域レベルは0〜1。`envelope` は持続振動、`taps` は瞬間振動、`spectrum` は20 Hz〜8 kHzの24帯域です。`analysis.serverTrackID` はPC保存IDで、`GET /tracks/{trackID}` に使用します。結果JSONを取得してもiPhoneの振動は自動で発生しません。振動を鳴らすにはResonなど、実機のCore Hapticsを扱うアプリが必要です。

- 1曲20分以内、1ファイル512 MiB以内（536,870,912バイト）。
- 未完了ジョブは最大8件、処理は1件ずつ。
- `jobID` はサーバー再起動で失効。保存した `trackID` と振動データは保持。
- 取得した音源は処理終了・失敗・キャンセル時に削除。保存データは `.pc-server/data/tracks/`。
- HTTP 400は入力不正・上限・待ち行列超過、401は認証または接続元、404は対象なし、500はサーバー内の失敗。
- ブラウザー向けのCORS設定はありません。連携にはPython等のHTTPクライアントを使います。

外部のAIに相談する際は、OS、実行したコマンド、接続キーを除いたエラーと `state` を伝えると切り分けできます。
