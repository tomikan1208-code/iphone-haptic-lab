# レイヤー再生とAHAP

Core Hapticsの1つのパターンには、重なった持続イベントと瞬間イベントを入れられる。「プレーヤーが1つ」だけで重ねがけ不可になるわけではない。[AppleのAHAP仕様](https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files)。

従来のサンプル画面は、新しい見本で前のプレーヤーを止めていた。現在は独立したプレーヤーを最大4つまで使い、個別に強さ・鋭さを変更して停止できる。4つはこのアプリの上限で、Taptic Engineのハードウェア上限を意味しない。音楽側は以前から持続とクリックを分けており、今回の編曲でもこの方式を使う。

## 触感を重ねる

1. メニューから「振動サンプル」を開く。
2. 「再生中の触感に重ねる」と「持続の見本を繰り返す」をオンにする。
3. 持続の見本を開始し、クリックを押して追加する。
4. 再生中のレイヤーの強さ・鋭さを操作し、不要なものだけ停止する。

繰り返しは最大60秒。振動調整画面でも、設定した触感をレイヤーとして追加できる。タブ移動・画面ロック・アプリ中断では全て停止する。

## AHAPの入出力

「AHAPを読み込んで再生」からファイルを選ぶ。重ねる設定がオンなら追加レイヤーとして再生する。見本の長押しから「AHAPを書き出す」を選ぶ。

| 要素 | 対応 |
| --- | --- |
| `HapticTransient` / `HapticContinuous` | 対応。同じ時刻の重なりも可 |
| `AudioContinuous` | 対応。Core Hapticsの合成音と振動が同じ時間軸で鳴る |
| `Parameter` | 対応。再生中の動的パラメータ変更 |
| `ParameterCurve` | 対応。曲線開始時刻＋相対時刻のcontrol pointsを保持 |
| `AudioCustom` / 外部音声ファイル | 今回は未対応。読み込み時に理由を表示 |
| サンプルの上限 | Version 1、2 MiB、30秒、256イベント、1曲線16点 |

`HapticIntensityControl`はイベント強度に掛かり、`HapticSharpnessControl`は鋭さへの加算値で-1〜1を取る。同じパターンの複数イベントへ制御が及ぶため、音楽では持続とアクセントのプレーヤーを分ける。自動曲線と再生中の変更を同じparameterへ送る場合、パターン内の後続の指定も適用される。実機で操作感を確認する。

独自の`Presets.json`はUIの名前・カテゴリと既存データのために残し、標準AHAPへ変換できるようにした。フォーマットと再生能力は別に扱う。

## 編曲した音楽のAHAP

PCは全曲を8秒以下のクリップへ分割し、持続用`bed`と瞬間用`accents`のAHAPとmanifestを保存する。

```powershell
.\.pc-server\venv\Scripts\python.exe pc-server\client.py export-ahap <trackID> --output .build\ahap-export
```

各クリップの2つのファイルを別プレーヤーへ載せ、manifestのstartに合わせて同じengine時刻で開始する。1つへ結合すると持続の曲線がクリックにも掛かるため、そのまま結合しない。音楽の音声はYouTube／元音源のプレーヤーで鳴らし、AHAPには含めない。iPhoneの音楽プレーヤーは短い区間を予約して同じ分離を行う。

[指定曲の56〜64秒の持続](verification/serenade-56s-bed.ahap)と[アクセント](verification/serenade-56s-accents.ahap)を用意している。これは同じ8秒を同時開始するためのペアで、曲の音声は含まない。
