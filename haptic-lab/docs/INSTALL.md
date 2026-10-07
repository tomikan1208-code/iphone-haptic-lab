# Resonを自分のiPhoneへ入れる

ResonはYouTube動画を振動付きで再生するiPhoneアプリです。音楽動画を主な用途として、音声から振動を作り、動画の時刻に同期して再生します。

## 対応と準備

| 持っているもの | 導入方法 |
| --- | --- |
| iPhone + Windows PC | ReleaseのIPAをSideloadlyで署名してインストール |
| iPhone + Mac | ReleaseのIPAをSideloadlyで署名、またはXcodeでソースをビルド |
| iPhoneだけ | この配布方法では、初回インストールと再署名にWindows / Macが必要 |
| Android | 現在のResonはiPhone専用。Android向けAPKはありません |

対象はiOS 16以降、Core Haptics対応のiPhone実機です。iPadやシミュレーターで同じ触感を再現することはできません。PCはインストール・無料署名の更新と、新規の音楽AI解析に使います。作成済みの振動はiPhoneに保存し、再生時はPC不要です。

ソース版2.8.1では、初回と作り直しに解析方法を確認し、iPhoneの精密解析かPCのAI編曲を選べます。高速解析は使えません。アプリの版、ソースコミット、Xcodeビルドとテスト結果はBUILD-INFO.jsonとTEST-SUMMARY.jsonで確認してください。iPhone実機の触感は未確認です。[指定曲のPC検証](verification/SERENADE.md)。

## 1. アプリを取得

1. [Resonの最新Release](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) を開きます。
2. **Assets** の `Reson-install.zip` をPCへダウンロードし、ZIPを展開します。`Source code (zip)` はアプリのソースで、インストール用IPAとは別です。
3. 展開した `HapticLab-unsigned.ipa` がインストール対象です。アプリ名はReson、HapticLabは内部名です。

ReleaseにはIPA単体もあります。初めての方には、手順・PCサーバー・APIサンプルが揃ったZIPをおすすめします。フォークから入れる場合は、そのフォークのReleasesを使用してください。まだReleaseがなければ [自分でビルドする手順](BUILD.md) に進みます。

Releaseの `SHA256SUMS.txt` とファイルのSHA-256を比較できます。Windowsでは `Get-FileHash .\Reson-install.zip -Algorithm SHA256`、Macでは `shasum -a 256 Reson-install.zip`。`BUILD-INFO.json` にバージョン、ソースコミット、ビルドURL、検証結果を記録します。

## 2. iPhoneへインストール

[Sideloadly公式サイト](https://sideloadly.io/)からPCのOSに合った版を入れ、必要なAppleの接続ソフトも公式サイトの案内に沿って用意します。Windowsの詳細は [Windows用手順](INSTALL-WINDOWS.md) を参照してください。

1. データ通信ができるケーブルでiPhoneを接続し、iPhone上でPCを信頼します。
2. SideloadlyでiPhoneを選択し、`HapticLab-unsigned.ipa` を指定します。
3. 自分のApple Accountを入力して **Start**。認証・2段階認証は自分でPC上で行います。
4. iPhoneの「設定 → 一般 → VPNとデバイス管理」で、署名した開発者アカウントを信頼します。
5. 「設定 → プライバシーとセキュリティ → デベロッパモード」をオンにし、再起動後の確認にも同意します。項目がない場合は、一度開発用アプリのインストール・起動を試します。
6. ホーム画面の **Reson** を開きます。

未署名のIPAは「ファイル」アプリで開くだけではインストールできません。上の署名操作が必要です。[AppleのDeveloper Modeの説明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

Macでソースから入れる場合は [Xcode手順](BUILD.md#macのxcodeから実機へ入れる) を使います。

## 3. 最初の動画で確認

1. [PC解析の手順](PC-SERVER.md)でAI環境を準備し、LANモードで起動します。
2. iPhoneと同じWi-Fiに接続し、「… → 解析方法・PCサーバー」にLAN URLと接続キーを設定します。
3. 「検索」に曲名やアーティスト名を入力し、公開の音楽動画を選びます。Googleログインは不要です。
4. 初回の「振動を作成中」が終了したら、動画・音・振動と一時停止を確認します。
5. 強さを調整し、「再生リスト → 作成済み」からもう一度開きます。2回目は保存した振動を使い、PCは不要です。

ネットワークやYouTubeの制限で解析できない場合は、右上「… → 振動サンプル」で端末の振動だけを先に確認できます。振動が出ない場合は「設定 → アクセシビリティ → タッチ → バイブレーション」と対応機種を確認します。詳しい操作は [使い方](MUSIC.md) へ。

## 4. 署名を更新

無料のApple Accountによる署名は7日間です。期限が切れたら、同じApple Account・同じアプリIDで再署名して上書きします。保存した振動や履歴を保つため、更新時にアプリを削除しないでください。Sideloadlyの自動更新は、PCが稼働してiPhoneへ接続できるときに使えます。[AppleのPersonal Teamの制限](https://developer.apple.com/help/account/basics/about-your-developer-account/)、[SideloadlyのFAQ](https://sideloadly.io/)。

## 必要なら追加

- [PC解析](PC-SERVER.md): 新規作成の音楽AI環境。同じWi-Fiと接続キーが必要。
- [HTTP API](API.md): プログラムから編曲した振動JSON・AHAPを取得する。
- [AHAPとレイヤー](AHAP.md): 持続とクリックを重ね、標準形式のパターンを入出力する。
- [Googleログイン](GOOGLE-LOGIN.md): 自分のYouTube再生リスト用。自分のOAuth設定を入れたビルドが必要。
- [AI向け導入ガイド](AI-INSTALL.md): AIに渡す依頼文と、よくある失敗の確認先。
