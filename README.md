# KifuLens / 棋譜レンズ

将棋の盤面、棋譜、端末内解析、定跡、Floodgate前例を閲覧するiPhoneアプリです。
既定の解析エンジンは、公開済みNAGISA v3.1です。
YaneuraOu系の別エンジンも、ソースと評価資産を用意して`engines.json`へ追加できます。
ShogiHub、OpeningStudio、前例DBの生成・日次更新サーバーは含みません。

- [公式ページ](https://keinoda.github.io/KifuLens/)
- [プライバシーポリシー](https://keinoda.github.io/KifuLens/privacy.html)

## 構成

| パス | 用途 |
| --- | --- |
| `KifuLens/` | アプリ本体 |
| `KifuLensTests/`、`KifuLensUITests/` | アプリ・画面のテスト |
| `engines.json` | 同梱するエンジン、評価資産、USIオプションの設定 |
| `Vendor/EngineBridge/` | 共通のiOS接続と静的ライブラリ生成 |
| `Vendor/NagisaV3Engine/Upstream/` | 既定エンジンの公開ソースsubmodule |
| `project.yml` | XcodeGenによるプロジェクト定義 |
| `docs/` | アプリ内の法務文書と公開案内ページ |

外部ソースは固定commitのsubmoduleです。

| submodule | 用途 | 元リポジトリ |
| --- | --- | --- |
| `Vendor/NagisaV3Engine/Upstream` | 公開NAGISA v3.1 | [keinoda/YaneuraOu](https://github.com/keinoda/YaneuraOu/tree/nagisa_v3) |
| `Vendor/SwiftShogi` | 局面・棋譜・定跡処理のKifuLens用派生版 | [keinoda/SwiftShogi](https://github.com/keinoda/SwiftShogi) |
| `Vendor/ShogiHome` | MITライセンスの木目盤画像 | [sunfish-shogi/shogihome](https://github.com/sunfish-shogi/shogihome) |

エンジンは公開commit `640f46561455436641b2eafb6fb75dfbeaf21f3f`
（`nagisa-v3.1`）に固定しています。非公開エンジンのソース・履歴は使用しません。
[iOS対応・エンジン追加の手順](Vendor/EngineBridge/README.md)は別途記載しています。

## ビルド

通常のアプリビルドにはmacOS、Xcode 26以降、XcodeGenを使用します。
CMake 3.25以降とPython 3.9以降は、別エンジンを追加・変更するときだけ必要です。
Apple SiliconとIntel Macのシミュレーター、およびA13以降のiPhoneを対象とします。

```sh
git clone --recurse-submodules https://github.com/keinoda/KifuLens.git
cd KifuLens
```

ngs_v3（NAGISA v3.1）の評価関数・進行度係数・iOS用のビルド済み静的ライブラリは同梱しています。
通常のビルドでは、エンジン生成用の`build.py`を実行する必要はありません。

| 同梱するもの | 配置先 |
| --- | --- |
| NAGISA v3.1の評価関数・進行度係数 | `KifuLens/EngineAssets/nagisa-v3/eval/` |
| device arm64 / simulator arm64・x86_64の静的ライブラリ | `Vendor/EngineBridge/Frameworks/KifuLensNative.xcframework/` |
| エンジン一覧と資産配置の定義 | `KifuLens/Generated/CompiledEngineConfiguration.swift`、`engine-resources.yml` |

以下の外部リソースは別途配置してください。これらはGitでは追跡しません。

| 配置先（リポジトリのルートから） | 内容 |
| --- | --- |
| `KifuLens/PolicyAssets/DLSuishoPolicyValue.mlmodel` | 対応するCore MLのpolicy/valueモデル |
| `KifuLens/VisualAssets/ShogiHome/Pieces/` | 下記のPNG駒画像。利用権のある画像を用意してください |
| `KifuLens/Resources/OpeningBooks/PetaShock233/user_book1.ybb.lzfse` | 同梱ペタショック定跡のLZFSE圧縮YBB |
| `KifuLens/Resources/FloodgateReference/` | 下記4ファイルのLZFSE圧縮前例DB |

駒画像は `black_` と `white_` を接頭辞に付けた次の13種類、および
`black_king2.png`（玉）・`white_king.png`（王）が必要です。画像枠内の駒の縮尺を揃えます。

```text
pawn.png  lance.png  knight.png  silver.png  gold.png  bishop.png  rook.png
prom_pawn.png  prom_lance.png  prom_knight.png  prom_silver.png  horse.png  dragon.png
```

Core MLの入力は `input1`（1×62×9×9）と `input2`（1×57×9×9）、
出力は `output_policy`（2187要素）と `output_value`（1要素）です。

前例DBのファイル名は次のとおりです。
[配布カタログ](https://drive.usercontent.google.com/download?id=1RP4G8sRo_5vWaiM-8TSPKWypaqoLcDsg&export=download&confirm=t)
から対応ファイルを確認できます。同梱する定跡・前例DBには
`BundledOpeningBook.swift` / `BundledOpeningReference.swift` の検証値と一致する版を使います。
別の定跡・前例DBはアプリ内のファイル選択から開けます。

```text
floodgate-4000-since-2023.osref.lzfse
floodgate-4000-since-2023-delta-20260617-20260625.osref.lzfse
floodgate-4000-since-2023-delta-20260626-20260813.osref.lzfse
floodgate-4000-since-2023-delta-20260814-20260905.osref.lzfse
```

標準エンジンの設定と生成物は用意済みです。外部リソースの配置後、
Xcodeプロジェクトを生成してアプリをビルドします。

```sh
xcodegen generate
xcodebuild -project KifuLens.xcodeproj -scheme KifuLens \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/kifulens-DerivedData build-for-testing
```

生成した `KifuLens.xcodeproj` をXcodeで開き、既存のiPhoneシミュレーターで実行できます。
シミュレーターのメモリ判定で起動を試せない場合は、DebugのScheme → Run →
Argumentsに `-ui-test-local-analysis-memory` を指定すると、検証用の利用可能量を1GiBとして扱います。
これは実RAMを予約する設定ではなく、既存のテスト用の起動引数です。
Releaseビルドのメモリ条件には影響しません。
実機ではReleaseを使用し、自分のTeamとBundle IDを指定します。例えば次のようにビルドできます。

```sh
xcodebuild -project KifuLens.xcodeproj -scheme KifuLens \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/kifulens-device-DerivedData \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  KIFULENS_BUNDLE_IDENTIFIER=your.bundle.identifier \
  -allowProvisioningUpdates build
```

XcodeからRunする場合は、同じ設定をBuild Settingsの`DEVELOPMENT_TEAM`と
`KIFULENS_BUNDLE_IDENTIFIER`へ指定してください。生成プロジェクト、署名用設定、
一時ビルド成果物はGitに含めません。作業が終わった一時DerivedDataは削除できます。

## テスト

設定の検証はPython標準ライブラリだけで実行できます。

```sh
python3 -m unittest discover -s Vendor/EngineBridge/Build/tests -v
```

アプリは、既存のシミュレーターを選んでXcodeのTest操作で確認できます。
エンジン構成の動作確認には次の対象を使用します。

- `ConfiguredEngineTests`: 設定にある全エンジンの起動、10万ノード探索、再起動、Policyとの共存
- `ConfiguredEngineUITests`: 設定から生成された選択肢を列挙し、それぞれを画面で選んで解析

既定構成では既存の`KifuLensTests`と`KifuLensUITests`も使用します。
公開NAGISA v3.1の資産を照合するテストには、[権利・資産情報](THIRD_PARTY_NOTICES.md)に
記載した参照版のリソースが必要です。エンジンを差し替えた場合は、構成に対応する
上記の汎用テストを実行してください。

## 別エンジンの同梱

対応するYaneuraOu系エンジンは、ソースをsubmoduleとして追加し、
`engines.json`のエンジン定義を追加・変更して再ビルドします。
エンジンの選択肢、評価資産の配置、USIオプションは自動生成されるため、
Swiftや`project.yml`へエンジンごとのコードを追加する必要はありません。

- [設定項目と対応範囲](Vendor/EngineBridge/README.md)
- [公開NAGISAと本家9.80を同梱する設定例](examples/engines.yaneuraou-9.80.json)

例をローカルで変更して使う場合は、`engines.local.json`へコピーし、
`python3 Vendor/EngineBridge/Build/build.py --config engines.local.json`を実行します。
追加の評価関数と`engines.local.json`はGitで追跡しません。
カスタム構成の生成は、標準同梱のライブラリ・一覧・資産配置定義を書き換えます。
公開用とは別のクローンで試すと、標準構成をそのまま保持できます。

## ライセンス

アプリとKifuLens用SwiftShogi派生版はGPLv3です。MIT由来のソースと盤画像の
表示は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)に保存しています。
NAGISA v3.1の評価関数・進行度係数と、対応するビルド済みiOSエンジンを同梱します。
購入駒画像、別エンジンの評価関数、Core MLモデル、定跡・前例DBは含めません。

GitHub Pagesは`main`ブランチの`docs/`を公開します。前例DBの配布先はGoogle Driveです。
