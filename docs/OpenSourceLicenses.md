# KifuLens オープンソースライセンス

KifuLensはGNU General Public License version 3（GNU GPLv3）で
配布されます。GNU GPLv3の全文は、アプリ内の「GNU GPL version 3」
から確認できます。

以下は、KifuLensに含まれる主なソフトウェアと素材の著作権表示、
出典およびライセンスです。

## KifuLens

- ライセンス: GNU GPL version 3
- 対応するソースコード: 各配布版で案内するKifuLens公開リポジトリ
  またはバージョン固定ソースアーカイブ

オブジェクトコードの配布開始時点で、その配布版に対応する完全な
ソースコードへアクセスできる状態にします。

## SwiftShogi

KifuLensには、`kk-no/SwiftShogi`を基にKifuLens向けに変更した
Swiftソースが含まれます。同リポジトリは`jiro/SwiftShogi`を
取り込んで開始された履歴を持ち、現在の将棋データ型および
棋譜形式処理には、`tsshogi`のTypeScript実装をSwiftへ移植した
部分が含まれます。

- kk-no/SwiftShogi
  - Copyright (c) 2025 Kohei Keino
  - 出典: https://github.com/kk-no/SwiftShogi
  - ライセンス: MIT License
- jiro/SwiftShogi（上流履歴）
  - Copyright (c) 2020 Jiro Nagashima
  - 出典: https://github.com/jiro/SwiftShogi
  - ライセンス: MIT License
- tsshogi
  - Copyright (c) 2023 Kubo, Ryosuke
  - 出典: https://github.com/sunfish-shogi/tsshogi
  - ライセンス: MIT License

同梱パッケージには、YaneuraOu由来のYBB互換コードも含まれるため、
パッケージ全体としての頒布条件はGNU GPL version 3です。
MIT由来部分の許諾および著作権表示は引き続き適用されます。
CSA通信対局機能は含みません。

## YaneuraOu

PackedSfenおよびバイナリ定跡互換コードはYaneuraOuを出典とします。

- プロジェクト: YaneuraOu
- 出典: https://github.com/yaneurao/YaneuraOu
- ライセンス: GNU GPL version 3
- 参照箇所:
  - `source/extra/sfen_packer.cpp`
  - `source/book/book.cpp`
- YBB導入commit:
  https://github.com/yaneurao/YaneuraOu/commit/4890e85390b1f3daa25818856e0e047c9eaad923

## NAGISA系エンジン

同梱するエンジンはビルド時のengines.jsonで決まります。
以下は、公開済みNAGISA v3を使用する既定構成の表記です。
標準の評価関数・進行度係数と、対応するiOS用の静的ライブラリを同梱しています。

- 公開版NAGISA v3: `NAGISA_V3 v3.1`
  https://github.com/keinoda/YaneuraOu/tree/nagisa_v3
- NAGISA v3エンジン版:
  `YANEURAOU_ENGINE_SFNN_halfkahm2_1024_15_64_ls9`
- エンジンライセンス: GNU GPL version 3
- 対応ソース:
  - `Vendor/NagisaV3Engine/Upstream`

評価関数および進行度係数については、本プロジェクトの所有者が
権利を有し、この配布ではGNU GPL version 3を適用します。

- NAGISA v3 `nn.bin`
  - サイズ: 78,442,142 bytes
  - SHA-256:
    `e6b0b6ac99e95922ceba11633cc8e329968b152d7a79910156405f8a7ea9cdb9`
- NAGISA v3 `progress.bin`
  - サイズ: 1,003,104 bytes
  - SHA-256:
    `e7ed0eef88868335f9a46c58a121dccb5ad82a5eb1c8ee12de90365ab351e37d`

各`progress.bin`は解析時に必要な実行時素材です。

## 新ペタショック定跡 233万局面

「新ペタショック定跡 233万局面」は上流のリリース名です。
KifuLensに同梱するデータベースの実測局面数は2,252,118です。

KifuLensは、YaneuraOuプロジェクトがMIT Licenseで公開した
`new_petabook_20250505c.7z` の `user_book1.db` を、YaneuraOuの
正式なYBB形式へ変換してLZFSEで圧縮し、既定の定跡として同梱します。
初回起動時に端末内のApplication Supportへ一度だけ展開し、以後は
展開済みYBBを再利用します。検索時には巨大な定跡全体をメモリへ
読み込まず、表示中の局面をオンデマンドで検索します。

- 公開者: やねうらお（GitHubアカウント: yaneurao）
- プロジェクト: YaneuraOu
- 出典:
  https://github.com/yaneurao/YaneuraOu/releases/tag/new_petabook233
- ライセンス: MIT License
- ライセンス根拠: 上記公式リリースにおけるMIT Licenseでの公開表明
- 元アーカイブ:
  - サイズ: 76,080,406 bytes
  - SHA-256:
    `158a891fcb685af65a7d633541b5af57eb085422ff26372d53f6d92158031fb3`
- YBB変換:
  - 変換器:
    https://github.com/yaneurao/YaneuraOu-ScriptCollection/blob/70ee2f956f93da5a2c9e606ea94c05305bd85c8c/makebook/convert_db_to_ybb.py
  - 変換器のライセンス: MIT License
  - 変換時にYBB仕様へ合わせ、評価値を-32,000〜32,000、深さを
    0〜9,999の範囲へ正規化
- 同梱する `user_book1.ybb.lzfse`:
  - サイズ: 85,263,832 bytes
  - SHA-256:
    `5ebf91f566e97084cc44dafbcda659eaa652862fd3cb8326aefb1cca831d66fa`
- 展開後の `user_book1.ybb`:
  - サイズ: 195,680,126 bytes
  - SHA-256:
    `915d72caeeffc347ead41c67905f8bdd97218cdec883ee463012105e61af6d08`
  - 実測局面数: 2,252,118
  - 実測指し手数: 16,097,817

上流のリリースおよび配布データには、独立した著作権者名または
著作権年の表示は確認できません。そのため、KifuLensでは
著作権者名および年を推定して付記せず、公開者、出典および
上流のライセンス表明を記録します。

## 購入済みライセンスの駒画像

KifuLensの駒画像は、プロジェクト所有者が商品ライセンスを購入した
`25667950.png` を、元の162 × 180 pxのセル単位で切り出したものです。
元画像のSHA-256は
`9d0646aa7554b94a299bb7e171a69135cac1b025bef1dc8a27b757380f53955c`
です。
再描画や画像生成は行っていません。再配布条件は購入した商品ライセンスに従います。
この駒画像自体をMIT LicenseまたはGPLで再許諾するものではありません。

## ShogiHomeの盤素材

KifuLensは、ShogiHomeの `wood_warm.png` 盤テクスチャを無改変で使用します。

- Copyright (c) 2022 Kubo Ryosuke
- 出典: https://github.com/sunfish-shogi/shogihome
- 参照revision: `f07e934a270622ff7219f9dd94d490ba3098dd68`
- 上流パス: `public/board/wood_warm.png`
- SHA-256:
  `7e7088f7287c6bf4044af665dab62d1c2f0a0fa0fe44464695910729cbc073c4`
- ライセンス: MIT License

参照revisionでは、上流パスにこの画像が存在し、リポジトリの
ルートMIT Licenseが適用されます。

## MIT License本文

次のMIT License本文は、上記のMIT License対象物に適用されます。
SwiftShogiおよびShogiHomeの著作権表示は各節に記載しています。
新ペタショック定跡については、上流に独立した著作権表示がないため、
公開者、出典および公式リリースのライセンス表明を記載しています。

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to
> deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
> sell copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
> FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
> DEALINGS IN THE SOFTWARE.
