# 音楽プレイヤー / HapticLab

iPhone SE（第3世代）で音楽・映像と保存した振動を再生するネイティブアプリです。SwiftUI + Core Hapticsで実装し、iOS 16以降のiPhoneに対応しています。

## できること

- 10種類の見本：クリック、ソフトタップ、二連打、心拍、雨つぶ、柔らかい持続、細かなざらざら、うねり、ためて弾ける、ミニドラム
- iOS標準の9種類の触感を比較
- 一瞬・持続・連打の振動を作成し、強さ・鋭さ・長さ・間隔を調整
- 40〜200 BPMの4拍リズム（1回最大60秒）
- 指の位置で強さ・鋭さが変わるパッド（1回最大20秒）
- お気に入りと調整値の保存
- 常時表示の停止ボタン、タブ切り替え・画面ロック・バックグラウンド移行時の停止

## 音楽機能（2.1）

- 初回の確認・音源解析と、振動・曲ごとの調整値の保存
- 音楽・動画ファイルの読み込み、直接HTTPS URLの解析とストリーミング再生
- YouTube公式プレーヤーと保存した振動の同期（PCは動画URLから初回解析、iPhoneは音源ファイル・音声URLから解析）
- Googleログインによる再生リスト選択（OAuth設定が必要）
- 作成済みリスト、アプリ内再生履歴、曲ごとのデータ削除
- 非公開のYouTube作成済みリストへの自動追加・削除と再試行
- 一時停止・シーク・読み込み待ちの同期、強さ・低音・ビート密度・同期補正
- 12秒のオリジナル音源で解析・保存・再生を確認
- 音楽中心の2タブと右上の振動ツールメニュー、キーボードに押し上げられない下部バー
- 縦画面の再生バーと振動の波形・フーリエ表示
- iPhone / PCの解析場所、音に追従 / リズム中心、標準 / オーケストラ向けを選択
- PCの振動キャッシュと1曲ずつの削除、解析の経過時間表示

YouTube全体の視聴履歴と解析用音声は公式APIで取得できません。PCのURL取得は非公式のyt-dlpを使い、動画の制限・YouTube側の変更で失敗することがあります。[音楽の使い方](docs/MUSIC.md)、[PCサーバーの起動](docs/PC-SERVER.md)、[Googleログイン設定](docs/GOOGLE-LOGIN.md)を参照してください。OAuth未設定でも音源ファイル・URL・アプリ内リストは利用できます。音楽AIは後の更新で扱います。

前のUIは `codex/music-haptics` ブランチと `dist/archive/2.0.0/` のIPAに残しています。同じApple Account・アプリIDで上書きすると保存データを引き継げます。

## Windowsで使う

完成した`HapticLab-unsigned.ipa`をSideloadlyで署名してiPhoneへインストールします。手順は[Windows用インストールガイド](docs/INSTALL-WINDOWS.md)を参照してください。

無料署名には、あなたがWindows上でApple Accountによる認証を行う必要があります。GitHubのビルドにAppleのパスワード・証明書・プロビジョニングプロファイルは不要です。

## ビルド

ソースは[非公開リポジトリ](https://github.com/tomikan1208-code/iphone-haptic-lab)に保存しています。[ビルド画面](https://github.com/tomikan1208-code/iphone-haptic-lab/actions/workflows/build-ios.yml)で実行状況とArtifactsを確認できます。アクセスには所有者のGitHubログインが必要です。

GitHubのActionsタブで`Build iPhone app`を実行すると、通常のmacOS runnerで次を行います。

1. Xcodeプロジェクト・アイコン・見本データを確認
2. 実機向けarm64アプリを未署名でビルドし、IPAへパッケージ化
3. iPhoneシミュレーターでパターンの検証と画面操作テスト
4. `HapticLab-iPhone`（IPA・手順・チェックサム）と`HapticLab-preview`（ネイティブ画面画像）をArtifactsに保存

macOSが利用できる場合は次のコマンドで同じビルドを実行できます。

```sh
node scripts/generate-project.mjs
node scripts/generate-music-demo.mjs
node scripts/generate-icons.mjs
node scripts/validate-project.mjs
bash scripts/build-ios.sh
bash scripts/test-ios.sh
```

WindowsでもNode.jsを使ってプロジェクトとリソースの整合性を確認できます。UIKit・Core HapticsのコンパイルにはmacOSのXcodeが必要です。

## 設計

- `HapticPattern.swift`：OSに依存しないパターンデータ、範囲検証、連打・メトロノームの生成
- `HapticController.swift`：Core Hapticsへの変換、単一プレーヤー管理、動的パラメーター、停止・中断・リセット対応
- `Resources/Presets.json`：触感の見本。時刻・持続時間は秒、強さ・鋭さは0〜1
- SwiftUIの各画面：見本、調整、パッド、使い方
- `MusicAnalyzer.swift`：PCMの順次処理、FFTによる低音・打音・音量解析
- `MusicModels.swift` / `MusicLibrary.swift`：全曲の振動データ、分割、保存と個別削除
- `MusicPlayback.swift`：AVPlayer・YouTubeの再生時刻とCore Hapticsの区間予約
- `HapticVisualization.swift`：保存した強度の波形、直近2.56秒の強弱の周波数表示
- `MusicComposer.swift`：リズムの構成とオーケストラ向けの持続・自然な打音
- `PCAnalysis.swift` / `pc-server/`：接続キーによるLAN通信、詳細な音源解析、保存と個別削除
- `GoogleOAuth.swift` / `YouTubeAccount.swift`：PKCE、Keychain、再生リスト取得・自動同期
- `Tests/`：不正な値、30秒制限、連打の時刻、メトロノーム末尾の無音区間を検証
- `UITests/`：小さい画面でタブ・スライダー・種類切り替え・停止を確認し、スクリーンショットを保存

見本のカスタムパターンは同時に1つだけです。音楽は持続とタップを分けた区間プレーヤーを使用します。停止は全体へ作用し、世代番号で古い完了通知が新しい再生を停止しないようにしています。

画面・ビルド・データの検証と、実際の触感の検証は別です。触感の質と実機での中断動作はiPhoneで確認してください。

音楽版2.0のビルド、24件のテスト、SE3サイズの画面確認、成果物と未検証範囲は[音楽版の検証結果](docs/MUSIC-VERIFICATION.md)にまとめています。[初版の検証記録](docs/VERIFICATION.md)も残しています。
