# 初版の検証結果

2026-10-05に、Windowsで作成したソースを承認済みの非公開GitHubリポジトリでビルドしました。

- ビルド対象のコミット：`50d56b1de1cdb22d5b446e61a3444920f4a71baf`
- [成功したクラウドビルド](https://github.com/tomikan1208-code/iphone-haptic-lab/actions/runs/37297959252)
- Xcode：16.4
- アプリの最低対応OS：iOS 16.0
- 実機向けReleaseビルド：arm64、署名なし
- シミュレーター：iPhone SE（第3世代）、iOS 26.2、375 × 667ポイント
- パターン・保存設定のテスト：7件成功
- タブ切り替え・スライダー・画面下の再生ボタン・停止のUIテスト：1件成功
- SE3サイズの画面画像を目視確認。調整画面の再生ボタンを常時表示し、パッドの数値を操作領域の上へ配置
- ダウンロードしたIPAのSHA-256、Payload構造、必要なリソース、arm64の実行ファイルを確認

## ローカルの成果物

- `dist/HapticLab-unsigned.ipa`：iPhone用のビルド済みアプリ。Sideloadlyで署名してインストールする
- `dist/INSTALL-WINDOWS.md`：インストールと無料署名の更新手順
- `dist/SHA256SUMS.txt`：IPAのチェックサム
- `dist/HapticLab-source.zip`：ソース一式
- `dist/preview/01-gallery.png`：見本画面
- `dist/preview/02-experiment.png`：調整画面
- `dist/preview/03-touch-pad.png`：触感パッド
- `dist/preview/04-guide.png`：使い方画面

IPAのSHA-256：

```text
6629c9ae2d6c18c3945f89ade8b7adb5f7862a6702a6bac122549266645fe7bb
```

## 実機で確認すること

シミュレーターは振動を出しません。SE3実機への署名・インストール、触感の質、実機での停止・画面ロック・中断動作は未確認です。[Windows用インストールガイド](INSTALL-WINDOWS.md)に最初の実機確認の手順をまとめています。

初版は触感の実験用です。音楽ファイルの読み込み・YouTubeとの連携は含まれません。
