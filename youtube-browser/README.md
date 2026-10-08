# Reson Web — YouTube専用ブラウザのUI試作

Resonを残したまま使える別のiPhoneアプリ。YouTubeの埋め込みプレイヤー・検索APIは使用せず、`https://www.youtube.com` を直接開く。

| アプリ | 表示名 | アプリ識別子 |
| --- | --- | --- |
| 今の振動プレイヤー | Reson | com.tomikan1208.hapticlab |
| このUI試作 | Reson Web | com.tomikan1208.resonweb |

識別子が異なるので共存できる。Resonの曲・解析・振動設定は変更しない。この試作には振動同期・既存データの移行機能はまだ含めない。

## UIと操作

黒い背景、Resonの配色、見出し直下の検索、右端のアカウントアイコン、検索／履歴／再生リストの3タブを使う。中央にはYouTubeの実ページを表示する。サイト内部のヘッダー、動画操作、広告、コメント、再生リストの見た目はYouTube側のまま。

- 検索: 曲名をYouTubeで検索する。YouTube動画URLもそのまま開ける。
- 履歴: YouTubeの `/feed/history` を開く。
- 再生リスト: YouTubeの `/feed/playlists` を開く。
- 右端のアカウント: YouTubeのアカウントページを開く。
- 「…」: 再読み込み／Safariで開く／バーをたたむ。
- 縦・横画面に対応する。動画の全画面機能はYouTubeページの操作を使う。

## ログインと履歴

永続的なWebサイト保存領域を使い、許可されたCookie・サイトのログイン状態を次回起動にも保持する。ただしGoogleはアプリ内WebViewからのGoogleログインを制限している。そのため、独自UIとYouTubeのログイン・履歴保存を両立できるとはまだ断定できない。[Googleの公式説明](https://developers.google.com/identity/siwg/best-practices)。

ログインが成立すればYouTube自身が履歴・再生リストを表示し、YouTubeの設定に応じて履歴を保存する。Safariのログイン状態はこのアプリのWebViewとは共有しない。Safariで開いたときの履歴はSafari側のYouTubeセッションに従う。Googleの認証画面にスクリプトを挿入したり、ブラウザ名を偽装したりしない。

UIを完全にResonへ統一するためにYouTubeのDOMを大きく書き換える方法は、サイト変更で壊れやすい。この試作では外側をResonに合わせ、サイト内部は直接操作する。

## ビルドと検証

iOS 16以降。Macで `bash scripts/build-and-test.sh` を実行する。独立した `ResonWeb.xcodeproj` とGitHub Actionsの `Build Reson Web prototype` を使う。配布IPAは未署名なので、Resonと同じ署名・インストール手順を利用する。ただし共存のためアプリ識別子をResonのものへ変更しない。

UIテストはオフラインのページで検索バー・タブ・表示切り替え・横画面を確認する。これは実際のGoogleログインやYouTubeの履歴書き込みの確認にはならない。ビルド結果とこの未確認項目は `BUILD-INFO.json` に記録する。実機では、ログイン成功 → 動画を再生 → YouTube履歴に表示 → アプリを終了して再起動 → ログインと履歴が残る、の順に確認してから移行を検討する。
