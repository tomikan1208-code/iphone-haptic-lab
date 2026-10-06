# Reson — YouTubeを振動付きで再生するiPhoneアプリ

Resonは、YouTube動画の音に合わせてiPhoneを振動させるプレーヤーです。音楽動画の再生を主な用途として、低音の響き、打音、曲の強弱を手でも感じられるようにします。

最初に動画の音声を解析して振動を保存し、再生時はYouTubeプレーヤーの時刻に合わせて振動を鳴らします。2回目からは保存した振動を使います。解析はiPhoneだけで完結し、PCサーバーとGoogleログインは必要な人が追加できます。

> **初めて使う方:** [Releasesからダウンロード](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) → [インストール手順](docs/INSTALL.md)。AIに導入を手伝ってもらう場合は [AI向け導入ガイド](docs/AI-INSTALL.md) の依頼文を使えます。

## 再生できること

- YouTubeの動画・チャンネル・公開再生リストを検索して選ぶ。
- 初回に音声を一時取得して解析し、振動と音の周波数データを保存する。解析後に一時音声を削除する。
- 動画の再生・一時停止・シークに振動を同期する。
- 全体の強さ、持続振動、瞬間振動、瞬間の鋭さ、ビート密度を曲ごとに調整する。
- 履歴と「再生リスト → 作成済み」から保存した曲を開く。
- 音に追従する振動、リズム中心、オーケストラ向けの仕上げを選ぶ。
- Googleログインを設定したビルドでは、自分のYouTube再生リストを利用する。

「振動サンプル」「振動を調整」「タッチパッド」は右上の「…」にある補助機能です。プロジェクト初期の触感実験ラボから、現在は動画プレーヤーへ発展しました。ソースやIPAの `HapticLab` という名前は、その頃の内部名です。ホーム画面のアプリ名は **Reson** です。

## 自分のiPhoneで使う

対象は **iOS 16以降、Core Hapticsに対応したiPhone実機** です。iPhone SE（第3世代）の画面を基準に作っています。Android版はありません。シミュレーターでは画面を確認できますが、実際の振動は体験できません。

1. [最新Release](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) の `Reson-install.zip` をPCへダウンロードして展開します。
2. Windows / macOSの [Sideloadly](https://sideloadly.io/) で、同梱の `HapticLab-unsigned.ipa` を自分のApple Accountで署名してiPhoneへ入れます。MacではXcodeからソースを実機へ入れる方法も使えます。
3. 開発者の信頼・デベロッパモードを設定し、Resonを開きます。
4. 「検索」で音楽動画を選びます。初回の振動作成が終わると、動画と振動を一緒に再生できます。

詳しくは [共通インストール手順](docs/INSTALL.md)、[Windowsの操作手順](docs/INSTALL-WINDOWS.md)、[音楽と振動の使い方](docs/MUSIC.md) を参照してください。無料署名は7日ごとに更新が必要です。Apple Accountの認証情報をGitHubやAIへ渡す必要はありません。[AppleのPersonal Teamの説明](https://developer.apple.com/help/account/basics/about-your-developer-account/)。

Releaseがまだない場合や自分で変更する場合は、[ビルド手順](docs/BUILD.md) に従って、自分のForkのGitHub ActionsかMacのXcodeでIPAを作れます。

## APIと追加設定

| 目的 | 必要なもの | ガイド |
| --- | --- | --- |
| 公開動画の検索・振動付き再生 | iPhoneアプリ | [使い方](docs/MUSIC.md) |
| PCで解析・結果を保存 | 自分のPC、uv、解析サーバー | [PCサーバー](docs/PC-SERVER.md) |
| 自分のプログラムやAIから解析 | PCサーバーの接続キー | [HTTP API](docs/API.md) / [OpenAPI 3.1](docs/api/openapi.json) |
| 自分のYouTube再生リスト | 自分のGoogle iOS OAuthクライアントを設定したビルド | [Googleログイン](docs/GOOGLE-LOGIN.md) |

基本の再生に、共有クラウドAPIや有料APIキーは必要ありません。PC解析APIは利用者のPCで動き、音源のアップロード、解析の進捗確認、振動JSONの取得に対応します。動作確認用の12秒音源と [Pythonサンプル](pc-server/client.py) を同梱しています。

YouTube音声の取得はiPhoneでは [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit)、PCでは [yt-dlp](https://github.com/yt-dlp/yt-dlp) を使います。動画の制限やYouTube側の変更で取得できない場合があります。Googleログインは [YouTube Data API](https://developers.google.com/youtube/v3) を使う別の機能です。

## 開発・配布

この公開リポジトリのアプリ本体は `haptic-lab/` にあります。ここに記載するコマンドは、このフォルダーから実行します。GitHub Actionsのワークフローはリポジトリ直下の `.github/workflows/build-ios.yml` です。

```sh
node scripts/generate-project.mjs
node scripts/generate-music-demo.mjs
node scripts/generate-icons.mjs
node scripts/validate-project.mjs
```

Mac + Xcodeでは、続けて `bash scripts/build-ios.sh` と `bash scripts/test-ios.sh` を実行できます。WindowsでXcodeのコンパイルはできませんが、自分のForkのActionsでビルドできます。Appleの証明書やパスワードはクラウドビルドに不要です。

ActionsはPC解析・API・ネイティブアプリを検証してIPAを作成します。配布時は `Reson-install.zip`、`BUILD-INFO.json`、`SHA256SUMS.txt` を含むReleaseを作ります。バージョン、ソースコミット、テスト結果、チェックサムを照合できます。[再ビルドとReleaseの手順](docs/BUILD.md)。

SwiftUI + Core Hapticsで実装しています。主な構成は、`MusicView.swift`（検索と準備）、`MusicPlayback.swift`（同期再生）、`MusicPrecisionAnalysis.swift`（iPhone解析）、`MusicLibrary.swift`（保存）、`PCAnalysis.swift` と `pc-server/`（PC解析API）です。

触感の強さや感じ方、YouTube動画との同期は実機でも確認してください。過去の検証記録は `docs/*VERIFICATION.md` にあります。AI向けの入口は [llms.txt](llms.txt) です。
