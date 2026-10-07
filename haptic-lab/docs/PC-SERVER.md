# ResonのPC音楽AI解析

PCのAI編曲を選ぶと、音楽を事前解析し、振動を追加の楽器として編曲する。新規作成でも追加解析でも解析方法を確認し、iPhoneだけで行う帯域別精密解析も選べる。高速解析は新規作成に使用しない。作成した振動はiPhoneにも保存するので、再生のためにPCを起動しておく必要はない。既存の高速／帯域解析の保存データも再生できる。

この手順はソース版2.8.3向け。配布物のBUILD-INFO.jsonでアプリの版とXcodeビルドのソースを確認する。iPhone実機の触感は未確認。[ビルド手順](BUILD.md)、[HTTP API](API.md)。

## 解析する内容

解析パイプライン`arrangement-3.4`は、複数拍でのテンポ推定、一対一の拍照合、重複拍の除去、小節内の周期・長さの検証を行う。拍子やテンポの変化は観測時刻で保持する。ドラムのオンセットが十分に支持する区間では16分シャッフルの細分音符を編曲に反映する。支持が弱い場合は補正しない。変更前の保存結果は残り、追加解析で改善版を使う。[指定曲での改善結果](verification/SERENADE-IMPROVED.md)。持続振動はベース・伴奏・声・ドラムを参照し、音がある小節のアクセント休止は緩やかな持続へ切り替える。[欠落と再解析の検証](verification/CONTINUITY-AND-REANALYSIS.md)。曲末尾などに20 ms未満の区間がある音源でも、区間の情報を初期化して解析・保存を完了する。[特定曲の失敗修正と検証](verification/SUB-FRAME-SECTIONS.md)。
| 処理 | モデル・アルゴリズム |
| --- | --- |
| ドラム・ベース・歌・その他の伴奏を分離 | HTDemucs |
| サビ・メロ・展開、拍、小節頭を推定 | All-In-One、Harmonixの8モデル |
| 拍・小節頭を別モデルで確認 | Beat This、final0 |
| 音の雰囲気を6種類の記述と比較 | CLAP。音声とテキストの埋め込み比較 |
| 持続・アクセント・休符の配置を決める | 制約付きのモチーフ探索。学習済み生成モデルではない |

LLMは使用しない。歌詞や作者の意図を理解したという意味ではなく、構造・音色・強弱・リズム・雰囲気の推定を編曲に使う。2つの拍モデルが一致しない区間は、固定拍を加えず持続中心へ切り替える。FFTは周波数の参考表示に残り、新しい振動を作る判断には使わない。[設計](HAPTIC-ARRANGEMENT-DESIGN.md)。

## このPCで確認した構成

Windows、NVIDIA RTX 3050（VRAM 8 GB）で全曲解析を実行した。Python 3.11のAI環境とPython 3.13の軽量HTTP環境を分け、PyTorch 2.5.1 / CUDA 12.4を使う。モデルを順に読み込み、各段階の終了後にGPUメモリを解放する。

指定曲「natori - Serenade」（217.74秒）の初回モデル取得後の処理は約47秒、旧版の同一音源のキャッシュ再利用は約4.4秒だった。現在の作成・追加解析では保存結果を再利用せず、毎回解析する。実測したPyTorchの最大割当量は約756 MiBで、ドライバー等も含めたGPU全体の使用量ではない。[検証結果](verification/SERENADE.md)。追加の2曲の処理時間は[特定曲の検証結果](verification/SUB-FRAME-SECTIONS.md)に記載した。他のPCでの速度は未測定。GPUがない場合はCPU推論へ切り替わるが、CPUでの待ち時間は未測定。

## 準備とWindowsでの起動

以下は `haptic-lab/` または対応する配布ZIPを展開したフォルダーから実行する。

[uv](https://docs.astral.sh/uv/getting-started/installation/) と固定した推論コードの取得用にGitを用意する。YouTube取得用には [Node.js](https://nodejs.org/en/download) も用意する。

```powershell
winget install --id astral-sh.uv -e
winget install --id Git.Git -e
winget install --id OpenJS.NodeJS.LTS -e
```

インストール後はPowerShellを開き直す。

フォルダー直下の `Start-PCServer.bat` をダブルクリックすると、iPhoneから接続できるLANモードでサーバーを起動する。起動後はこのウィンドウを閉じてもサーバーは動き続ける。既に起動済みの場合はそのまま使う。

起動ウィンドウにはHTTP接続URLと接続キーを表示する。開いたままにしておくと、iPhoneから開始した解析の曲名、進捗率、処理内容、完了・失敗・キャンセルを表示する。進捗率は処理段階の目安で、AI推論中は数値が変わらない場合がある。同じ処理が続く場合も15秒ごとに表示を更新する。iPhone側にも進捗率と処理内容を表示する。Ctrl+Cは進捗表示だけを終了する。

PowerShellから起動する場合は次のコマンドを使う。

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-server\Start-PCServer.ps1 -Lan
```

PowerShellでも進捗を表示する場合は `-Watch` を追加する。起動済みサーバーの表示だけを開く場合は `powershell -ExecutionPolicy Bypass -File .\pc-server\Show-PCServer.ps1 -Watch` を使う。

初回起動でライブラリを導入する。モデルの重みは初回解析時にダウンロードし、以降は `.pc-server/models/` を再利用する。初回だけは実測の47秒より長くなる。依存関係とモデルの保存用に十分な空き容量が必要。Windowsへの自動起動登録は行わない。

CPU版を明示的に導入する場合は、先に実行する。

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-server\setup-ml.ps1 -CPU
```

停止は次のコマンド。保存済みの振動は保持する。

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-server\Stop-PCServer.ps1
```

## macOS / Linux

起動用スクリプトを用意しているが、この変更のAI環境はmacOS / Linuxでは実行検証していない。macOSはCPU版、LinuxはCUDA版を標準としている。

```sh
bash pc-server/start.sh --lan
```

LinuxでCPU版を選ぶ場合は先に `bash pc-server/setup-ml.sh --cpu` を実行する。ターミナルは開いたまま使い、停止はCtrl+C。

PC自身でAPIだけを使う場合は `-Lan` / `--lan` を省くと127.0.0.1で待ち受ける。ポート変更はWindowsで `-Port 8766`、macOS / Linuxで `--port 8766`。

## iPhoneから接続

1. iPhoneとPCを同じWi-Fiへ接続する。
2. PCの `.pc-server/connection.json` で `addresses` のLAN URLと `token` を確認する。接続キーは自分のアプリへ入力し、チャットやGitHubへ貼らない。
3. Reson右上「… → 解析方法・PCサーバー」で、batに表示されたHTTP URLと接続キーを入力し、「設定を保存」「接続を確認」を押す。URLは消去・貼り付け・キーボード入力で変更できる。
4. ローカルネットワークへのアクセスを許可する。
5. 曲を選ぶと解析方法の確認画面を開く。「PCでAI編曲」を選び、作成ボタンを押すと解析を開始する。iPhoneで精密解析する場合はPCへ接続しない。作成済みの曲へ別の解析を追加する場合は、曲のメニューから「別の解析を追加」を選ぶ。以前の振動を残し、再生画面の調整で切り替える。

`health` の `arrangementAvailable` が `true` ならAI環境を確認済み。未設定の場合はエラーを表示し、旧FFT方式へ自動で切り替えない。標準／オーケストラ向けのプロファイルは選べる。

接続できない場合はLANモード、PCのIP、WindowsのプライベートネットワークでのPython通信許可、iPhoneのローカルネットワーク権限を確認する。iPhoneからの127.0.0.1はPCを指さない。ゲストWi-Fiの端末間通信制限やVPNも接続に影響する。

## 保存と削除

- `.pc-server/data/tracks/`：振動のversion 3 JSON、解析グラフ、編曲スコア。
- `.pc-server/data/exports/<trackID>/`：持続用／アクセント用AHAPとmanifest。[AHAPの使い方](AHAP.md)。
- `.pc-server/models/`：ダウンロードしたモデル。
- `.pc-server/data/working/<jobID>/`：処理状態とworkerログ。

取得・アップロードした音源、分離した音源、スペクトログラムは成功・失敗・キャンセル時に削除する。公開する検証資料には音声を含めない。保存IDにはデコードした音声のSHA-256、モデル・パイプラインの版、プロファイル、ジョブIDを含める。同じ音源・設定でも解析結果を別々に保存し、以前の結果は上書きしない。作成・追加解析は毎回AI処理を実行する。

アプリのPC設定で保存データを1曲ずつ削除できる。PCから削除してもiPhoneの保存データは残る。PCの削除は対応するスコア・グラフ・AHAPも対象になる。ログは `.pc-server/server.log`、`server-error.log`、各ジョブの `worker.log`。接続キー、ログ、音源、モデルキャッシュはGitと配布ZIPから除外する。

## モデルの出典と固定した実装

| 対象 | 出典・使用版 |
| --- | --- |
| All-In-One | [元の実装](https://github.com/mir-aidj/all-in-one)、[Windowsで使用する推論移植](https://github.com/openmirlab/all-in-one-infer/tree/8414233b743d6ccec46e36ab4cfeddb4605ff3bf)、Harmonixの既存重み |
| Demucs | [Metaの実装](https://github.com/facebookresearch/demucs)、[使用する移植](https://github.com/openmirlab/demucs-infer/tree/ffe0080ef96336a34e3f0ee8ba22ceaa0623a36c)、htdemucs |
| Beat This | [作者の実装](https://github.com/CPJKU/beat_this)、1.1.0 / final0 |
| CLAP | [LAIONの実装](https://github.com/LAION-AI/CLAP)、[使用する重み](https://huggingface.co/laion/clap-htsat-unfused/tree/8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a) |

All-In-OneとDemucsの移植版は、元の学習済み重みを使い、Windowsで動くPyTorchの演算を使う。元実装との数値同一性は検証していない。使用ライブラリは [requirements-ml.txt](../pc-server/requirements-ml.txt) に固定した。

Beat Thisの作者配布先がこの環境から名前解決できなかったため、[固定リビジョンのミラー](https://huggingface.co/rtikw/localmusic-assets/tree/a44f51ed621bc9895c15f8b46194cf16d7b22b66/analysis)を代替取得先にしている。取得前後に既知SHA-256 `8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331` を照合し、一致しない重みは使わない。検証で使用した重みのハッシュは [metrics](verification/serenade-metrics.json) に保存した。
