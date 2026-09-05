# iOSエンジンの静的ビルド

`engines.json`から、エンジンをまとめた一つの静的XCFramework、Swiftのエンジン一覧、
アプリへコピーする評価資産を生成します。標準のNAGISA v3.1には生成済みの
ライブラリと評価関数を同梱しているため、通常はこの生成処理を実行せずアプリをビルドできます。
アプリから起動する探索エンジンは常に一つです。
推定選択率には`policyEngine`で指定したエンジンの盤面処理と、既存Core MLモデルを使用します。

## 対応範囲

YaneuraOu系のNNUEエンジンを対象とします。既定の公開NAGISA v3.1と、
本家[YaneuraOu 9.80の公開commit](https://github.com/yaneurao/YaneuraOu/commit/d47c9bfb94210fb1f9b741d5ee16ce081b35cacd)
用のiOSパッチを用意しています。前者は進行度係数あり、後者の設定例は進行度係数なしの構成です。

ソースには`source/engine/yaneuraou-engine/`、`USIEngine`、`Position`、
`nnue_arch_gen.py`など、この接続層が使用するAPIが必要です。
APIが異なる独自エンジンやYaneuraOuの別世代では、iOSパッチ・CMakeのソース一覧・
C++接続部への対応も必要です。USIに対応しているという条件だけでは設定のみで同梱できません。
既存の実行ファイルをアプリ内から読み込む機能はありません。

## 設定項目

パスはKifuLensリポジトリのルートを基準にします。絶対パスも指定できます。

| 項目 | 内容 |
| --- | --- |
| `defaultEngine` | 最初に選択するエンジンのid |
| `policyEngine` | Core MLの特徴量・合法手処理を担当するエンジンのid |
| `engines` | 同梱するエンジン定義の配列 |
| `id` | 重複しない英小文字・数字・ハイフンの識別子。英字で開始 |
| `displayName` / `version` | アプリに表示する名前とバージョン |
| `commentName` | 棋譜コメントのエンジン名。省略時はdisplayName |
| `source` | `source/config.h`が入っているソースリポジトリ |
| `patch` | ビルド用コピーへ適用するiOSパッチ |
| `architecture` | 評価関数に対応するNNUE architecture名 |
| `nnue` | 手元の評価関数ファイル。生成時に`nn.bin`として配置 |
| `progress` | 進行度係数ファイル。不要なエンジンでは項目を省略 |
| `options` | エンジン固有のUSIオプション名と値の辞書 |
| `defines` | 必要な追加コンパイラー定義の配列。通常は省略 |

`options`の値は文字列・整数・真偽値です。`@progress`はBundle内の進行度係数の
パスに展開されます。`Threads`、`USI_Hash`、`MultiPV`、`EvalDir`はアプリ側が
管理するため、ここでは指定しません。対応しないUSIオプションを指定すると起動時にエラーになります。

評価関数のarchitecture、FV_SCALE、bucket設定は、その評価関数の指定に合わせます。
ファイル名だけでは互換性を判定できません。本家9.80のk3k3はarchitectureに含まれる
固定のbucket構成であり、`LS_BUCKET_MODE`を送信する設定にはしていません。

## 本家9.80を追加する例

ソースをsubmoduleとして追加し、参照commitを固定します。

```sh
git submodule add https://github.com/yaneurao/YaneuraOu.git Vendor/YaneuraOu980
git -C Vendor/YaneuraOu980 checkout d47c9bfb94210fb1f9b741d5ee16ce081b35cacd
cp examples/engines.yaneuraou-9.80.json engines.local.json
```

この例は`SFNN_halfka2_1024_7_64_k3k3`に対応する評価関数とFV_SCALE 40を前提にしています。
利用できる評価関数を用意し、`engines.local.json`の`nnue`をそのパスに変更してください。
評価関数本体はこのリポジトリに含まれません。別の形式を使用する場合はarchitectureとoptionsも変更します。

```sh
python3 Vendor/EngineBridge/Build/build.py --config engines.local.json --check
python3 Vendor/EngineBridge/Build/build.py --config engines.local.json
xcodegen generate
```

この設定例はNAGISA v3とYaneuraOu 9.80の両方を登録します。
別のクローンで変更を試すと、元のクローンの標準同梱物を保持できます。
同じクローンで標準構成を再生成する場合は、`--config`を付けずに同じ生成処理を実行します。
変更した設定でビルドし直すまでは、アプリの同梱エンジンは変わりません。

## 生成物とiOS対応

- `.build-engines/`: 各スライスの一時ソースコピー・コンパイル結果
- `Vendor/EngineBridge/Frameworks/KifuLensNative.xcframework`: 静的ライブラリ
- `KifuLens/Generated/CompiledEngineConfiguration.swift`: エンジン一覧・資産サイズ・USI設定
- `engine-resources.yml`: 今回の構成でアプリに含めるエンジンの資産フォルダ
- `KifuLens/EngineAssets/<id>/eval/`: 評価資産。配置定義にあるエンジンだけをアプリへコピー

`.build-engines/`と個別に追加する評価関数はGitに含めません。
標準NAGISAの資産・静的ライブラリ・Swift定義・配置定義は、クローン直後から使える状態で同梱します。
生成される定義は手編集せず、変更時は`engines.json`を編集して再生成します。
submoduleのファイルは変更せず、コピーへパッチとNNUEヘッダー生成を適用します。
設定と入力ファイルを検証してから処理を開始します。

同梱ライブラリは公開NAGISA v3.1のcommit `640f46561455436641b2eafb6fb75dfbeaf21f3f` と、
本リポジトリのiOS接続から生成したものです。評価関数は`SFNN_halfkahm2_1024_15_64_ls9`、
FV_SCALE 28、progress8kpabsを使用します。水匠11Plusなどの追加評価関数は同梱しません。

既定ではdevice arm64、simulator arm64/x86_64の全スライスを生成します。
シミュレーターだけの場合は`--platform simulator`、実機だけの場合は`--platform device`を指定できます。
片方だけの生成物を他方へ使用する場合は、必要なスライスを含めて再生成してください。
`--jobs`で並列コンパイル数を指定でき、省略時はMacのCPU数を使用します。

各エンジンの名前空間と評価関数の読込状態を分離し、C接続を一つのライブラリに集約します。
USIスレッド終了後も残る評価関数キャッシュは、実際の読込とreadyokで確認したパスだけを再利用します。
探索・評価アルゴリズムをこの接続層で変更することはありません。

## トラブルシューティング

- ファイルが見つからない: 設定内のパス、submoduleの初期化、外部資産の配置を確認します。
- パッチが適用できない: 指定したソースの世代とパッチが対応しているかを確認します。
- 標準の定義やXCFrameworkが見つからない: 同梱ファイルを取得できているか確認します。カスタム構成の場合は`build.py`を完了してからXcodeGenを実行します。
- `No such option`: そのエンジンの`usi`応答にないオプションをoptionsから取り除きます。
- 評価関数の読込に失敗: architectureと評価関数の形式、FV_SCALE、進行度係数の要否を確認します。
- シミュレーターのメモリ判定で停止: READMEのDebug専用引数を指定します。実RAMの予約設定ではありません。

設定を変更した後は、`ConfiguredEngineTests`と`ConfiguredEngineUITests`で全エンジンを確認します。
候補が表示されたことだけでなく、探索が進むこと、切替後の結果とPolicyが保たれることを検査します。
