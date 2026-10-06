# ResonのPC解析サーバー

ResonはiPhoneだけでYouTube動画の振動を作成・再生できます。PC解析は処理を自分のPCへ任せたい場合の追加機能です。作成した振動はiPhoneにも保存し、作成後の再生にPCは不要です。プログラムから使う場合は [HTTP API](API.md) を参照してください。

PC解析は44.1 kHz・10 ms間隔、低音4096 FFT・打音1024 FFTです。iPhoneにも同じサンプル周波数・時間間隔の「精密（帯域別）」があり、「高速」は22.05 kHz・20 msです。音に追従／リズム中心、標準／オーケストラ向けを選べます。GPUやクラウド推論は使いません。

## 準備

[Release](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) の `Reson-install.zip` を展開するとサーバーも入っています。ソースから使う場合は、リポジトリの `haptic-lab/` フォルダーを開きます。以下のコマンドはそのフォルダー、またはZIPを展開したフォルダーから実行します。

[uv](https://docs.astral.sh/uv/getting-started/installation/) をインストールしてください。起動スクリプトがPython 3.13と必要な解析ライブラリを用意します。YouTubeの取得も行う場合は [Node.jsのLTS版](https://nodejs.org/en/download) も用意してください。ファイル解析にはNode.jsは不要です。

WindowsのPowerShell:

```powershell
winget install --id astral-sh.uv -e
```

インストール後はPowerShellを開き直します。Node.jsもWinGetで入れる場合は `winget install --id OpenJS.NodeJS.LTS -e`。MacでHomebrewを使っている場合は `brew install uv`、Node.jsも必要なら `brew install node`。Linuxはuvの公式インストール手順を使ってください。

## Windowsで起動

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-server\Start-PCServer.ps1 -Lan
```

初回は依存ライブラリをダウンロードします。起動後は接続先と `.pc-server/connection.json` の場所を表示します。Windowsへの自動起動登録は行いません。

停止:

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-server\Stop-PCServer.ps1
```

## macOS / Linuxで起動

```sh
bash pc-server/start.sh --lan
```

このターミナルを開いたまま使い、停止は **Ctrl+C**。iPhoneアプリのインストールはWindows / Macが必要ですが、解析サーバーはLinuxでも動かせます。

PC自身でAPIだけを試す場合は `-Lan` / `--lan` を省くと127.0.0.1のみで待ち受けます。ポート変更はWindowsで `-Port 8766`、Mac / Linuxで `--port 8766`。

## iPhoneから接続

1. iPhoneとPCを同じWi-Fiへ接続します。
2. PCの `.pc-server/connection.json` を開き、`addresses` のPCのLAN URLと `token` を確認します。接続キーは自分のアプリへ入力し、チャットやGitHubへ貼らないでください。
3. Reson右上「… → 解析方法・PCサーバー」でURLと接続キーを入力し、**接続を確認** を押します。
4. iPhoneがローカルネットワークへのアクセスを求めたら許可します。
5. 解析する場所を **PCで精密解析** に切り替えます。作成済みの動画なら、曲のメニューの **振動を作り直す** でPC解析を選びます。

接続できない場合は、LANモードで起動したか、PCのIPが変わっていないかを確認します。iPhoneからの `127.0.0.1` はPCを指しません。Windowsでは信頼するプライベートネットワークでこのPythonサーバーの通信を許可し、iPhoneでは「設定 → アプリ → Reson」のローカルネットワークを確認してください。ゲストWi-Fiの端末間通信制限やVPNも接続に影響します。

## 動作確認・保存データ

まずは [APIの12秒音源の例](API.md#最短で試す) でファイル解析を確認できます。YouTube音源の一時取得は [yt-dlp](https://github.com/yt-dlp/yt-dlp) を使い、動画の制限や仕様変更で失敗する場合があります。

解析後の音声は削除し、振動は `.pc-server/data/tracks/` へ保存します。アプリの **解析方法・PCサーバー → 接続を確認** の下で、PCの保存データを1曲ずつ削除できます。PCから削除してもiPhoneの保存データは残ります。サーバーを停止しても保存した振動は保持します。

ログは `.pc-server/server.log`、`.pc-server/server-error.log`、`.pc-server/data/working/<解析ID>/worker.log`。接続キー、ログ、キャッシュはGitと配布ZIPから除外します。接続キーはGoogle認証とは別です。
