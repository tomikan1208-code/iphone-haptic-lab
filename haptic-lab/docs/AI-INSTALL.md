# AIにResonの導入を手伝ってもらう

次の依頼文をコピーし、OS・機種・iOSバージョンを自分の環境へ置き換えて、利用しているAIへ送ってください。

```text
https://github.com/tomikan1208-code/iphone-haptic-lab のResonを自分のiPhoneで使いたいです。
ResonはYouTube動画（主に音楽）を振動付きで再生するアプリです。
PCはWindows 11、iPhoneはSE第3世代、iOSは自分の端末のバージョンです。
リポジトリのREADME、llms.txt、haptic-lab/docs/INSTALL.mdを読んで、
最新Releaseが目的の機能を含むか確認し、入手からSideloadlyでの署名、デベロッパモード、
PCの音楽AI環境の準備と接続、最初の動画の再生まで案内してください。
Releaseがない場合はhaptic-lab/docs/BUILD.mdのFork + GitHub Actionsの手順を使ってください。
Apple Accountの認証と2段階認証は私がPC上で行います。
まず不足している環境情報を確認し、今実行する操作を順番に説明してください。
```

APIも使いたい場合は、追加で次を送れます。

```text
ResonのPC解析APIも使いたいです。
haptic-lab/docs/PC-SERVER.md、haptic-lab/docs/API.md、
haptic-lab/docs/api/openapi.json、haptic-lab/pc-server/client.pyを読んでください。
PCサーバーを起動し、同梱のMusicDemo.wavから振動JSONを取得できるところまで案内してください。
接続キーはローカルのconnection.jsonから読み込んでください。
```

## AIが案内に使う事実

- 製品名は **Reson**。目的はYouTube動画の音と振動の同期再生。**HapticLab** は内部名。
- iOS 16以降、Core Haptics対応のiPhone実機が必要。Android版とブラウザー版はない。
- 初回インストールにはWindows / Macとデータケーブルを用意する。未署名IPAをiPhoneで開くだけでは入らない。
- 配布先はReleases。`Reson-install.zip` または `HapticLab-unsigned.ipa` を使う。GitHubの `Source code` はIPAではない。
- 無料署名は7日。更新は同じApple Account・同じアプリIDで上書きし、保存データを保持する。
- 検索・公開動画の再生にGoogleログインや共有APIキーは不要。
- ソース版2.8.3では、初回と作り直しに解析方法を確認する。iPhoneの帯域別精密解析かPCの音楽AI編曲を選べる。高速解析は使えない。AI編曲はLLMではない。Windows / RTX 3050で指定曲全体を検証済み。
- PC接続は `-Lan` / `--lan`、同じWi-Fi、LAN URL、接続キー、ローカルネットワーク権限が必要。作成済みの振動の再生にはPC不要。
- アプリの版、ソースコミット、Xcodeビルドとテスト結果はBUILD-INFO.jsonとTEST-SUMMARY.jsonで確認する。iPhone実機の触感は未確認。[検証](verification/SERENADE.md)を参照。
- Googleログインを使う場合は、自分のiOS OAuthクライアントIDを入れて再ビルドする。共通の開発者キーは配布しない。
- 接続キー、Apple Accountのパスワード、認証コード、Googleトークンはチャット・GitHub・Issueへ記載しない。
- リポジトリ直下とアプリの `haptic-lab/` を区別する。コマンドは各ガイドが指定したフォルダーで実行する。
- 正常終了の基準は、実機で動画と振動が再生できること。PC APIの場合は12秒音源の解析結果JSONを取得できること。

## 詰まったときの確認先

| 状況 | 次に確認すること |
| --- | --- |
| Releaseが見つからない | [Forkしてビルド](BUILD.md)。所有者限定のアクセスや未公開の配布を前提にしない |
| iPhoneがSideloadlyに出ない | データケーブル、PCの信頼、Appleの接続ソフト、[Sideloadly公式案内](https://sideloadly.io/) |
| 「信頼されていない開発者」 | 設定 → 一般 → VPNとデバイス管理 |
| デベロッパモードを求められる | 設定 → プライバシーとセキュリティ → デベロッパモード |
| 数日後にアプリが開かない | 無料署名の期限。同じApple Account・アプリIDで再署名 |
| 音は出るが振動が出ない | 対応機種、端末のバイブレーション設定、アプリの強さ、振動サンプル |
| YouTubeの振動作成に失敗 | 動画の制限・ネットワーク。別の公開動画、APIなら同梱音源で切り分ける |
| PCにつながらない | 同じWi-Fi、LANモード、PCのIP、接続キー、プライベートネットワークのFirewall許可、iPhoneのローカルネットワーク権限 |
| APIが401 | `.pc-server/connection.json` の接続キーと `Authorization: Bearer …` を確認 |
| Googleログインが利用できない | [OAuth設定](GOOGLE-LOGIN.md) を入れたIPAか、実際のバンドルIDとの一致 |

エラーの相談にはPCのOS、iPhoneの機種・iOS、導入したReleaseのバージョン、行った操作、接続キーを除いたエラーメッセージを添えてください。
