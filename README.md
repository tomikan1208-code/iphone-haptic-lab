# 触感ラボ / HapticLab

iPhone SE（第3世代）で、Taptic Engineの触感を体験・調整するネイティブアプリです。SwiftUI + Core Hapticsで実装し、iOS 16以降のiPhoneに対応しています。

## できること

- 10種類の見本：クリック、ソフトタップ、二連打、心拍、雨つぶ、柔らかい持続、細かなざらざら、うねり、ためて弾ける、ミニドラム
- iOS標準の9種類の触感を比較
- 一瞬・持続・連打の振動を作成し、強さ・鋭さ・長さ・間隔を調整
- 40〜200 BPMの4拍リズム（1回最大60秒）
- 指の位置で強さ・鋭さが変わるパッド（1回最大20秒）
- お気に入りと調整値の保存
- 常時表示の停止ボタン、タブ切り替え・画面ロック・バックグラウンド移行時の停止

初版は触感を試すためのアプリです。音楽ファイルの解析・再生やYouTube連携は今後の段階です。画面内の波形は触感のイメージを表す図です。

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
- `Tests/`：不正な値、30秒制限、連打の時刻、メトロノーム末尾の無音区間を検証
- `UITests/`：小さい画面でタブ・スライダー・種類切り替え・停止を確認し、スクリーンショットを保存

同時に再生するカスタムパターンは1つだけです。新しい再生時に前のプレーヤーを停止し、世代番号で古い完了通知・タイマーが新しい再生を停止しないようにしています。音楽同期に拡張するときも、解析から同じパターンデータを生成できる構成です。

画面・ビルド・データの検証と、実際の触感の検証は別です。触感の質と実機での中断動作はiPhoneで確認してください。

初版のビルド、8件のテスト、SE3サイズの画面確認、成果物の記録は[検証結果](docs/VERIFICATION.md)にまとめています。
