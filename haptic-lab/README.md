# Reson / HapticLab

iPhone SE（第3世代）で音楽・映像と保存した振動を再生するネイティブアプリです。SwiftUI + Core Hapticsで実装し、iOS 16以降のiPhoneに対応しています。

## できること

- 10種類の見本：クリック、ソフトタップ、二連打、心拍、雨つぶ、柔らかい持続、細かなざらざら、うねり、ためて弾ける、ミニドラム
- iOS標準の9種類の触感を比較
- 一瞬・持続・連打の振動を作成し、強さ・鋭さ・長さ・間隔を調整
- 40〜200 BPMの4拍リズム（1回最大60秒）
- 指の位置で強さ・鋭さが変わるパッド（1回最大20秒）
- お気に入りと調整値の保存
- 常時表示の停止ボタン、タブ切り替え・画面ロック・バックグラウンド移行時の停止

## 音楽機能（2.7）

- 初回の確認・音源解析と、振動・曲ごとの調整値の保存
- 直接HTTPS URLの解析とストリーミング再生、保存済み音楽・動画ファイルの再生
- 黒と緑のUI、下部の「検索・履歴・再生リスト」で画面を切り替え
- YouTubeの動画・チャンネル・公開再生リスト検索（ログインなしでも利用可能）
- チャンネルの動画・再生リスト、再生リスト内の動画と続きを選択
- アプリ名のすぐ下に検索バーを表示し、アカウントアイコンを上部バーの右端に配置
- 動画選択時に「振動を作成中」の専用画面を開き、最小化後も下部に進捗を表示
- YouTube音声を1 MBずつ取得し、容量・速度・残り時間を表示
- 再生画面で全体の強さを0〜400%に調整。弱い曲を増幅でき、曲ごとに保存・再解析不要
- 持続振動・瞬間振動・瞬間の鋭さ・ビート密度を独立して調整。持続を抑えたまま打音を強くできる
- 「打音をくっきり」で全体80%・持続25%・瞬間100%・瞬間の鋭さ90%・ビート密度100%を適用
- 動画を選択 → iPhoneで音声を一時取得 → 解析 → 振動保存 → 音声削除
- 44.1／48 kHzステレオを明示的に変換し、有効な音声フレーム数と元の時刻で解析。旧方式のYouTube振動は選択時に一度作り直し、倍率・履歴を保持
- iPhoneだけで精密解析：44.1 kHz・10 ms、低音4096 FFT／打音1024 FFT、低音3帯域と低・中・高域Fluxで触感を作り分け。新規解析の標準にし、高速解析も選択可能
- YouTube公式プレーヤーと保存した振動・帯域データの同期
- 読み込み中や別の動画の長さによる誤判定を防止。不一致中は振動を待機し、本編の長さが一致したら自動再開
- Googleログインによる再生リスト選択（OAuth設定が必要）
- 「再生リスト」の「作成済み」に保存した曲を表示、アプリ内再生履歴、曲ごとのデータ削除
- 非公開のYouTube作成済みリストへの自動追加・削除と再試行
- 一時停止・シーク・読み込み待ちの同期、強さ・低音・ビート密度・同期補正
- 右上の「…」から振動サンプル・振動調整・タッチパッド・使い方を開く
- キーボードに押し上げられない下部バー
- 初期表示は音の周波数（20 Hz〜8 kHz・24帯域）。灰色は音、緑は同時刻の振動への反映
- 20 msごとの再生時刻と描画、前後2秒の振動波形と打音マーカー
- iPhone / PCの解析場所、音に追従 / リズム中心、標準 / オーケストラ向けを選択
- PCの振動キャッシュと1曲ずつの削除、準備時間とiPhoneの解析処理時間を記録

YouTube音声の取得にはiPhone内で動く[YouTubeKit](https://github.com/alexeichhorn/YouTubeKit)、PCではyt-dlpを使います。公開動画でも動画の制限・YouTube側の変更で失敗することがあります。[音楽の使い方](docs/MUSIC.md)、[PCサーバーの起動](docs/PC-SERVER.md)、[Googleログイン設定](docs/GOOGLE-LOGIN.md)を参照してください。OAuth未設定でも動画検索・ファイル・アプリ内リストは利用できます。既存の振動は引き継ぎますが、旧データの周波数表示には再解析が必要です。

Gitは親フォルダ、アプリは `haptic-lab/` に配置します。以下のコマンドはアプリのフォルダから実行してください。GitHub Actionsは親フォルダの `.github/workflows/` から起動し、`haptic-lab/` 内でビルドします。

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
- `MusicAnalyzer.swift`：PCMの順次処理、低音・中低音・高域解析、音の24帯域を保存
- `MusicPrecisionAnalysis.swift`：iPhoneの44.1 kHz／10 ms精密解析、低音3帯域と帯域別打音の触感マッピング
- `MusicModels.swift` / `MusicLibrary.swift`：全曲の振動データ、分割、保存と個別削除
- `MusicPlayback.swift`：AVPlayer・YouTubeの再生時刻とCore Hapticsの区間予約
- `HapticVisualization.swift`：保存した音の周波数、振動の強さ、前後2秒の波形
- `YouTubeMedia.swift` / `YouTubeBrowse.swift`：端末内の音声ストリーム取得と動画・チャンネル・再生リストの検索・閲覧
- `YouTubeAudioDownload.swift` / `MusicPreparationStatus.swift`：音声の分割取得と作成状況の表示
- `MusicComposer.swift`：リズムの構成とオーケストラ向けの持続・自然な打音
- `PCAnalysis.swift` / `pc-server/`：接続キーによるLAN通信、詳細な音源解析、保存と個別削除
- `GoogleOAuth.swift` / `YouTubeAccount.swift`：PKCE、Keychain、再生リスト取得・自動同期
- `Tests/`：不正な値、30秒制限、連打の時刻、メトロノーム末尾の無音区間を検証
- `UITests/`：小さい画面でタブ・スライダー・種類切り替え・停止を確認し、スクリーンショットを保存

見本のカスタムパターンは同時に1つだけです。音楽は持続とタップを分けた区間プレーヤーを使用します。停止は全体へ作用し、世代番号で古い完了通知が新しい再生を停止しないようにしています。

画面・ビルド・データの検証と、実際の触感の検証は別です。触感の質と実機での中断動作はiPhoneで確認してください。

今回の確認範囲は[2.4の検証記録](docs/PLAYER-2.4-VERIFICATION.md)を参照してください。[2.3の検証記録](docs/PLAYER-2.3-VERIFICATION.md)、[2.2の検証記録](docs/PLAYER-2.2-VERIFICATION.md)、[2.1の検証結果](docs/PLAYER-VERIFICATION.md)、[音楽版2.0の検証結果](docs/MUSIC-VERIFICATION.md)、[初版の検証記録](docs/VERIFICATION.md)は以前の版の記録です。
