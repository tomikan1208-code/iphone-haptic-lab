# Reson — YouTubeを振動付きで再生するiPhoneアプリ

Resonは、YouTube動画の音に合わせてiPhoneを振動させるプレーヤーです。音楽動画の再生を主な用途として、低音の響き、打音、曲の強弱を手でも感じられるようにします。

初回と作り直しでは、解析方法を確認してから開始します。iPhoneの帯域別精密解析、またはPCで楽器・拍・サビ・曲の雰囲気をAI解析して振動を編曲する方法を選べます。iPhoneへ保存後は、PCなしでYouTubeの時刻に同期して再生します。LLMやクラウド推論は使いません。Googleログインは自分の再生リストを使う場合の追加設定です。

このソースは2.8.4です。動画の上スワイプ・端末の横向きで全画面にし、横画面の下スワイプ・縦向きで戻せます。縦画面の下スワイプや「閉じる」はミニプレイヤーに戻し、検索・履歴・再生リストへ移動しても再生を続けます。同じ曲の解析結果と調整設定は引き続き保存・切り替えできます。Xcodeビルドとテスト結果は配布物のBUILD-INFO.jsonとTEST-SUMMARY.jsonで確認できます。iPhone実機の触感は未検証です。[調査・設計](docs/HAPTIC-ARRANGEMENT-DESIGN.md)、[欠落と再解析の検証](docs/verification/CONTINUITY-AND-REANALYSIS.md)。

> **初めて使う方:** [Releasesからダウンロード](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) → [インストール手順](docs/INSTALL.md)。AIに導入を手伝ってもらう場合は [AI向け導入ガイド](docs/AI-INSTALL.md) の依頼文を使えます。

## 再生できること

- YouTubeの動画・チャンネル・公開再生リストを検索して選ぶ。
- PCでHTDemucsの楽器分離、All-In-Oneの曲構造推定、Beat Thisの拍追跡、CLAPの音声・属性比較を実行する。
- モチーフ・変奏・歌との重なり・休符を選び、持続とアクセントの振動を編曲する。
- 振動・区間・周波数表示を保存し、取得音源と分離音声は削除する。
- 動画の再生・一時停止・シークに振動を同期する。
- 全体の強さ、持続振動、瞬間振動、瞬間の鋭さ、ビート密度を曲ごとに調整する。
- 全曲のグローバル振動設定を保存し、曲の個別調整からワンボタンでグローバルへ戻す。
- 履歴と「再生リスト → 作成済み」から保存した曲を開く。
- サビ候補や間奏の区間を表示し、その区間へ移動する。
- 標準／オーケストラ向けの仕上げを選ぶ。
- 振動サンプルを最大4レイヤーで重ね、AHAPを読み書きする。
- Googleログインを設定したビルドでは、自分のYouTube再生リストを利用する。

「振動サンプル」「振動を調整」「タッチパッド」は右上の「…」にある補助機能です。プロジェクト初期の触感実験ラボから、現在は動画プレーヤーへ発展しました。ソースやIPAの `HapticLab` という名前は、その頃の内部名です。ホーム画面のアプリ名は **Reson** です。

## 自分のiPhoneで使う

対象は **iOS 16以降、Core Hapticsに対応したiPhone実機** です。iPhone SE（第3世代）の画面を基準に作っています。Android版はありません。シミュレーターでは画面を確認できますが、実際の振動は体験できません。

1. [最新Release](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) の `Reson-install.zip` をPCへダウンロードして展開します。
2. Windows / macOSの [Sideloadly](https://sideloadly.io/) で、同梱の `HapticLab-unsigned.ipa` を自分のApple Accountで署名してiPhoneへ入れます。MacではXcodeからソースを実機へ入れる方法も使えます。
3. 開発者の信頼・デベロッパモードを設定し、Resonを開きます。
4. 「検索」で音楽動画を選び、確認画面でiPhoneの精密解析かPCのAI編曲を選びます。AI編曲の場合は[PCサーバー](docs/PC-SERVER.md)を設定します。作成後は、保存した振動と動画を再生できます。

詳しくは [共通インストール手順](docs/INSTALL.md)、[Windowsの操作手順](docs/INSTALL-WINDOWS.md)、[音楽と振動の使い方](docs/MUSIC.md) を参照してください。無料署名は7日ごとに更新が必要です。Apple Accountの認証情報をGitHubやAIへ渡す必要はありません。[AppleのPersonal Teamの説明](https://developer.apple.com/help/account/basics/about-your-developer-account/)。

Releaseがまだない場合や自分で変更する場合は、[ビルド手順](docs/BUILD.md) に従って、自分のForkのGitHub ActionsかMacのXcodeでIPAを作れます。

## APIと追加設定

| 目的 | 必要なもの | ガイド |
| --- | --- | --- |
| 公開動画の検索・保存済み振動の再生 | iPhoneアプリ | [使い方](docs/MUSIC.md) |
| 新しい振動をAIで編曲 | 自分のPC、uv、解析サーバー | [PCサーバー](docs/PC-SERVER.md) |
| 触感を重ねる・AHAPを交換 | iPhoneアプリ | [AHAPとレイヤー](docs/AHAP.md) |
| 自分のプログラムやAIから解析 | PCサーバーの接続キー | [HTTP API](docs/API.md) / [OpenAPI 3.1](docs/api/openapi.json) |
| 自分のYouTube再生リスト | 自分のGoogle iOS OAuthクライアントを設定したビルド | [Googleログイン](docs/GOOGLE-LOGIN.md) |

基本の再生に、共有クラウドAPIや有料APIキーは必要ありません。PC解析APIは利用者のPCで動き、音源のアップロード、解析の進捗確認、振動JSONの取得に対応します。動作確認用の12秒音源と [Pythonサンプル](pc-server/client.py) を同梱しています。

新規のYouTube音声取得はPCの [yt-dlp](https://github.com/yt-dlp/yt-dlp) を使います。動画の制限やYouTube側の変更で取得できない場合があります。Googleログインは [YouTube Data API](https://developers.google.com/youtube/v3) を使う別の機能です。

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

SwiftUI + Core Hapticsで実装しています。`music_ai.py`（音楽AI）、`haptic_arrangement.py`（モチーフ編曲とAHAP）、`MusicModels.swift`（version 3の触覚譜）、`MusicPlayback.swift`（同期する独立レイヤー）、`HapticAHAP.swift`（AHAP入出力）が中心です。旧データと内部テストのための端末解析コードは残し、新規作成の画面からは外しています。

触感の強さや感じ方、YouTube動画との同期は実機でも確認してください。過去の検証記録は `docs/*VERIFICATION.md` にあります。AI向けの入口は [llms.txt](llms.txt) です。
