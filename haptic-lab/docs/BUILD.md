# ソースからビルド・配布する

Resonのソースは [公開リポジトリ](https://github.com/tomikan1208-code/iphone-haptic-lab) にあります。アプリは `haptic-lab/`、Actionsはリポジトリ直下 `.github/workflows/` です。WindowsにはXcodeがないため、IPAの作成はGitHubのmacOS runnerまたは自分のMacで行います。

## 自分のForkのActionsでIPAを作る

1. リポジトリ右上の **Fork** で自分のコピーを作ります。
2. 自分のForkの **Actions** を開き、ワークフローが無効なら有効にします。
3. **Build iPhone app → Run workflow** を開き、目的のソースがあるブランチを選びます。新しい導入・API機能を含むブランチを使用してください。
4. `release_tag` を空欄のまま実行します。通常のビルドではReleaseを作成しません。
5. 実行が成功したら、画面下の **Artifacts → HapticLab-iPhone** をダウンロードして展開します。ArtifactsのダウンロードにはGitHubログインが必要です。
6. `HapticLab-unsigned.ipa` を [インストール手順](INSTALL.md) で署名して実機へ入れます。

Apple Account、署名証明書、プロビジョニングプロファイル、Google OAuthは通常のビルドに不要です。Googleログインも使う場合にだけ、ForkのRepository variable `GOOGLE_IOS_CLIENT_ID` を設定します。[設定方法](GOOGLE-LOGIN.md)。GitHub Actionsの利用枠・料金・macOS runnerの条件は自分のアカウントの設定を確認してください。

## MacのXcodeから実機へ入れる

MacにXcodeとNode.jsを用意します。Xcodeの対応OSやダウンロードは [Apple公式](https://developer.apple.com/xcode/) を確認してください。

```sh
git clone https://github.com/tomikan1208-code/iphone-haptic-lab.git
cd iphone-haptic-lab/haptic-lab
node scripts/generate-project.mjs
node scripts/generate-music-demo.mjs
node scripts/generate-icons.mjs
node scripts/validate-project.mjs
open HapticLab.xcodeproj
```

1. Xcodeの設定 **Accounts** に自分のApple Accountを追加します。
2. **HapticLab** ターゲットの **Signing & Capabilities** で自分の **Team** を選択し、Automatically manage signingを有効にします。
3. バンドルIDの登録エラーが出たら、自分が使える一意のIDへ変更します。Google OAuthを使う場合は登録したIDも一致させます。
4. iPhoneをケーブルで接続・信頼し、実行先にそのiPhoneを選びます。
5. **Run** で実機へ入れます。必要に応じて [開発者の信頼・デベロッパモード](INSTALL.md) を設定します。

プロジェクトの再生成は手動のTeam設定を上書きするため、生成コマンドはXcodeの署名設定より先に実行してください。無料署名は期限後の再ビルド・再インストールが必要です。

## ローカルの検証と未署名IPA

Macのアプリフォルダーで、上の生成・検証に続けて実行します。

```sh
bash scripts/build-ios.sh
bash scripts/test-ios.sh
```

PC解析とAPIのテストはPython 3.13の環境で行います。Windows / macOS / Linuxで実行できます。

```sh
python -m pip install -r pc-server/requirements-dev.txt
python -m unittest discover -s pc-server -p 'test_*.py' -v
```

Macのビルドとテストが成功したら `python scripts/package-release.py --source-commit "$(git rev-parse HEAD)"` で `.build/artifact/Reson-install.zip` を作ります。未commitの変更は先にcommitしてください。アーカイブにはIPA、導入ガイド、OpenAPI、PCサーバー、サンプルクライアント、12秒の確認用音源が入り、個人設定・接続キー・音源キャッシュは入りません。

## GitHub Releasesへ配布

リポジトリへ書き込める所有者・メンテナーが実行します。

1. `HapticLab/Info.plist` のバージョンとビルド番号を確認し、配布する変更をcommit / pushします。
2. **Actions → Build iPhone app → Run workflow** でそのコミットを含むブランチを選びます。
3. `release_tag` にアプリのバージョンと一致する新しいタグ（例: `v2.7.0`）を指定します。使用済みのReleaseタグには上書きしません。
4. PC解析、OpenAPI、iPhone向けビルド、シミュレーターのテスト、パッケージ作成がすべて成功すると、同じソースコミットを指すタグとReleaseを作ります。
5. ReleasesでIPA、`Reson-install.zip`、`BUILD-INFO.json`、`SHA256SUMS.txt`、導入ガイドを確認します。公開リポジトリのReleaseはGitHubログインなしで取得できます。

ビルドは `contents: read`、Releaseの作成ジョブだけが `contents: write` を使用します。通常のpush・Forkでの試用は配布を伴いません。Artifactは14日間保持します。公開配布には保持期限のあるArtifactではなくReleaseを案内します。[GitHubのRelease管理](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
