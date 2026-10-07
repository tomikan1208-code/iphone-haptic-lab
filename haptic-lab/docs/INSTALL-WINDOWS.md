# WindowsからResonをiPhoneへ入れる

ResonはYouTube動画（主に音楽）を振動付きで再生するアプリです。iOS 16以降、Core Hapticsに対応したiPhone実機を使います。全体の流れは [共通インストール手順](INSTALL.md)、再生操作は [使い方](MUSIC.md)、追加のPC解析は [PC-SERVER.md](PC-SERVER.md) を参照してください。

最初に [最新Release](https://github.com/tomikan1208-code/iphone-haptic-lab/releases/latest) の **Assets → Reson-install.zip** をWindowsへダウンロードして展開します。中の `HapticLab-unsigned.ipa` が対象です。GitHubの `Source code (zip)` はIPAではありません。Releaseがない場合は [Fork + Actionsでビルド](BUILD.md) できます。

## 最初にあなたが行う操作

無料署名には、あなたのApple Accountでの認証が必要です。アカウント情報はWindows上のSideloadlyに入力します。チャットやGitHubに入力する必要はありません。

1. [Sideloadly公式サイト](https://sideloadly.io/)からWindows用Sideloadlyをインストールする。
2. 公式サイトの案内に従い、必要なAppleの接続ソフト（iTunes・iCloud等）を用意する。対応する配布版はSideloadlyの最新案内を優先する。
3. データ通信ができるLightningケーブルでiPhoneをPCに接続する。
4. iPhoneに「このコンピュータを信頼しますか？」が出たら信頼し、端末のパスコードで確認する。
5. Sideloadlyを開き、対象のiPhoneを選ぶ。
6. `HapticLab-unsigned.ipa`をSideloadlyへドラッグする。
7. 自分のApple Accountでログインし、「Start」で署名・インストールする。2段階認証が出たらあなた自身で確認する。
8. iPhoneの「設定 → 一般 → VPNとデバイス管理」で、署名に使用した開発者アカウントを信頼する。
9. iPhoneの「設定 → プライバシーとセキュリティ → デベロッパモード」をオンにして再起動し、再起動後の確認にも同意する。項目がまだなければ、一度開発用アプリのインストール・起動を試してから確認する。
10. ホーム画面の「Reson」を開く。

IPAはビルド済みのアプリをまとめたファイルです。未署名のIPAを「ファイル」アプリで開くだけではインストールできません。Sideloadlyが、あなたのアカウントで署名して実機へ転送します。

## 7日ごとの更新

無料のApple Accountでは署名の有効期間は7日です。期限が切れたアプリは起動できなくなりますが、同じApple Account・同じアプリIDで署名を更新できます。

- Sideloadlyの自動更新を有効にすると、PCが動作中でiPhoneにUSBまたは設定済みのWi-Fi接続でアクセスできるとき、期限が近いアプリを更新します。
- PCが長期間オフラインなら自動更新はできません。その場合はPCに接続して再署名します。
- 更新時は元のアプリを削除せず、同じApple Accountと同じアプリIDで上書きします。作成した振動・音源・履歴・設定を保持するためです。
- 無料署名のアプリは端末あたり最大3つです。通常のApp Storeアプリはこの枠に含まれません。

## 最初の動作確認

ソース版2.8.3では、下部バーの「検索」でYouTube動画を選ぶと解析方法の確認画面を開きます。iPhoneの精密解析ならPCは不要です。PCのAI編曲なら、先に[PCの音楽AI環境](PC-SERVER.md)を起動し、batに表示されたHTTP URLと接続キーをアプリのPC設定へ入力・保存します。作成ボタンを押してから解析を開始します。保存した曲は「再生リスト」→「作成済み」から開けます。2回目に解析が始まらないこと、停止・10秒移動・強さの調整・曲ごとの削除を確認します。再生画面の右上の調整で持続・瞬間の強さと鋭さを変更できます。配布物の版とビルド・テスト結果はBUILD-INFO.jsonとTEST-SUMMARY.jsonで確認してください。実機の触感は未確認です。

1. 右上「…」→「振動サンプル」で「クリック」「ソフトタップ」の違いを確認する。
2. 「やわらかい持続」と「細かなざらざら」を比べる。
3. 右上「…」→「振動を調整」で強さ・鋭さを調整し、再生する。
4. 右上「…」→「タッチパッド」を押したまま動かし、指を離すと止まることを確認する。
5. リズムの再生中に下の「停止」を押す。
6. 再生中に画面をロックするか別アプリへ移動し、振動が止まり、戻っても勝手に再開しないことを確認する。

振動が出ない場合は「設定 → アクセシビリティ → タッチ → バイブレーション」を確認してください。シミュレーターでは触感を体験できません。

## 公式の参照先

- [Sideloadly公式FAQ](https://sideloadly.io/)：対応OS、無料署名7日、接続、自動更新、開発者の信頼設定
- [Appleの無料アカウントの制限](https://developer.apple.com/help/account/basics/about-your-developer-account)：7日、端末あたり3アプリ
- [AppleのDeveloper Mode解説](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

クラウドでのビルドにはApple Accountの認証情報を使いません。GitHub Actionsの利用枠・料金条件はGitHub側のアカウント設定によります。
