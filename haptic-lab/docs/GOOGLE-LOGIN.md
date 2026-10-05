# Googleログインを有効にする

GoogleのiOS用OAuthクライアントIDが必要です。パスワードやクライアントシークレットの埋め込みは不要です。[Googleの公式手順](https://developers.google.com/identity/protocols/oauth2/native-app)。

1. Google Cloudの自分のプロジェクトで **YouTube Data API v3** を有効にします。
2. Google Auth Platformで同意画面を設定し、Testing状態なら利用するアカウントをテストユーザーに追加します。
3. OAuthクライアントを **iOS**、バンドルID `com.tomikan1208.hapticlab` で作成します。署名ツールがIDを変更する場合は実際のIDと登録を一致させてください。
4. `数字-文字列.apps.googleusercontent.com` というクライアントIDを控えます。
5. GitHubリポジトリの **Settings → Secrets and variables → Actions → Variables** に `GOOGLE_IOS_CLIENT_ID` というRepository variableを作り、IDを値に入れます。
6. `codex/music-player` ブランチで `Build iPhone app` を実行して、新しいIPAを上書きインストールします。

ローカルでは `Configuration/GoogleOAuth.example.json` を `Configuration/GoogleOAuth.local.json` へコピーし、`clientID` に値を入れて `node scripts/generate-project.mjs` を実行します。localファイルはGitから除外しています。環境変数 `GOOGLE_IOS_CLIENT_ID` がある場合はそちらを優先します。逆順のコールバックスキームも自動設定します。

最初に `youtube.readonly` を要求し、自動追加を有効にする際に `youtube.force-ssl` を追加します。認証にはASWebAuthenticationSession、PKCE S256、stateを使用し、トークンをKeychainへ保存します。[OAuthポリシー](https://developers.google.com/identity/protocols/oauth2/policies)。

接続解除では端末の認証情報を削除してGoogleへ失効リクエストを送ります。通信で届かない場合は[Googleの接続管理](https://myaccount.google.com/connections)から解除できます。音楽ライブラリは端末に残り、曲ごとに削除できます。専用のYouTubeリストは解除時には削除しません。

クライアントIDなしのビルドでは実アカウントのログイン・リスト取得・自動追加は未検証です。設定後に実機で同意、再ログイン、追加・重複防止・削除・通信復帰を確認してください。OAuthのTesting設定・審査・期限・API利用枠による失敗はアプリ内に表示し、保存した振動を維持します。
