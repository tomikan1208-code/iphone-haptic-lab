# 音楽版2.0の検証結果

2026-10-05に、非公開GitHubリポジトリの `codex/music-haptics` ブランチで音楽版をビルドしました。

これは旧版2.0の記録です。この版の配布物は `dist/archive/2.0.0/` へ保存済みです。現在の配布物は[音楽プレイヤー2.1の検証結果](PLAYER-VERIFICATION.md)を参照してください。

- アプリのバージョン：2.0.0（ビルド2）
- 検証したアプリのコミット：`abc21f82426d154961792b91bae1b609ed3fd358`
- [成功したビルドとテスト](https://github.com/tomikan1208-code/iphone-haptic-lab/actions/runs/37309098619)
- Xcode：16.4、最低対応OS：iOS 16.0
- 実機向けRelease：arm64、署名なし。Sideloadlyで署名して既存アプリに上書きする
- シミュレーター：iPhone SE（第3世代）、iOS 26.2、375 × 667ポイント
- 単体テスト21件、画面操作テスト3件、計24件成功。失敗・スキップなし

## 確認した内容

音楽の単体テスト14件では、実際のPCM音源の解析、保存後の読み直し、曲ごとの削除、キャンセル時の途中データ除去を確認しました。無音、左右逆位相の低音、既知の打音、音声の先頭・末尾の無音時間、不正なURLや保存データ、一時停止・再生時刻の停滞、シークと速度変更、区間境界のタップ重複を検証しています。密な振動曲線から実際に `CHHapticPattern` を作成できることも確認しました。既存の触感パターンの7件も成功しています。

画面操作テストでは、初回の確認からサンプルの解析・保存、アプリ再起動後の保存済み再生、停止、個別削除を確認しました。不正なURLとOAuth未設定の案内、既存タブの操作も確認しています。SE3サイズの音楽ホーム・初回確認・作成済み・再生・アカウント画面を目視確認しました。

ダウンロードしたIPAのSHA-256、バージョン・バンドルID・最低OS、arm64実行ファイル、12秒のPCMサンプル、10種類の見本、アセットを確認しました。

IPAのSHA-256：

```text
b4eca50fb962d22991404625824d1daa901f3c4e8ede8c08ab25b0c2cec8e61b
```

## 成果物

- `dist/HapticLab-unsigned.ipa`：音楽版のインストール用アプリ
- `dist/INSTALL-WINDOWS.md`：上書きインストールと署名更新の手順
- `dist/MUSIC.md`：初回解析、保存済み再生、調整・削除の使い方
- `dist/GOOGLE-LOGIN.md`：Google Cloudと再ビルドの設定手順
- `dist/BUILD-INFO.json` / `dist/TEST-SUMMARY.json`：ビルドとテストの記録
- `dist/SHA256SUMS.txt`：IPAのチェックサム
- `dist/HapticLab-source.zip`：ソースと設定例
- `dist/preview/00-music.png`、`05-first-preparation.png`、`06-music-prepared.png`、`07-music-player.png`、`08-youtube-account.png`：音楽機能の画面
- `dist/archive/1.0.0/`：上書き前の初版の成果物

## 未検証の範囲

初版の実機振動はユーザー確認済みです。音楽版の触感の質、音声との同期、画面ロック・着信・Bluetooth等の実機動作は今回のシミュレーターテストでは検証できません。「音楽」から12秒サンプルを作成して実機で確認してください。

GoogleのiOS用OAuthクライアントIDは未作成のため、このIPAではGoogleログインを無効にしています。アカウントへのログイン、実際の再生リスト取得・自動作成・追加・削除は設定後に検証する必要があります。実装と設定手順を同梱し、音源ファイル・直接URL・アプリ内の作成済みリストと履歴は利用できます。

YouTubeの初回解析には、動画と同じ内容・開始位置の音源ファイルが必要です。YouTube全体の視聴履歴は取得せず、アプリ内で再生した履歴を保存します。YouTubeの広告や再生制限、ネットワーク遅延を含む同期精度は未検証です。制約と使い方は [MUSIC.md](MUSIC.md)、設定は [GOOGLE-LOGIN.md](GOOGLE-LOGIN.md)を参照してください。
