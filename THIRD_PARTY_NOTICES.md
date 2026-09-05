# Third-party notices

## SwiftShogi

KifuLens includes modified Swift sources derived from `kk-no/SwiftShogi`.
The upstream repository began with code imported from `jiro/SwiftShogi`.
Its current shogi data types and record-format implementation also contain
Swift ports of TypeScript code from `tsshogi`.

- kk-no/SwiftShogi — MIT
  (`Vendor/SwiftShogi/LICENSES/Kohei-Keino-MIT.txt`,
  https://github.com/kk-no/SwiftShogi)
- jiro/SwiftShogi (upstream history) — MIT
  (`Vendor/SwiftShogi/LICENSES/Jiro-Nagashima-MIT.txt`,
  https://github.com/jiro/SwiftShogi)
- tsshogi — MIT
  (`Vendor/SwiftShogi/LICENSES/Kubo-Ryosuke-MIT.txt`,
  https://github.com/sunfish-shogi/tsshogi)

The copyright and permission notices for all three lineages are preserved.

The vendored package additionally contains YaneuraOu-derived YBB compatibility
code. Accordingly, the package as a whole is distributed under GNU GPL
version 3. The MIT grants and copyright notices for the MIT-derived portions
remain in effect. CSA network play and protocol connection code are not
included.

## YaneuraOu

The PackedSfen and binary opening-book compatibility code is derived from
YaneuraOu and distributed under GNU GPL version 3.

- Project: YaneuraOu
- Source: https://github.com/yaneurao/YaneuraOu
- License: GPLv3
- Adapted source:
  - `source/extra/sfen_packer.cpp`
  - `source/book/book.cpp`
- YBB introduction commit:
  https://github.com/yaneurao/YaneuraOu/commit/4890e85390b1f3daa25818856e0e047c9eaad923
- License text:
  `Vendor/SwiftShogi/LICENSES/YaneuraOu-GPLv3.txt`

KifuLens as a whole is distributed under GPLv3. The MIT notices above remain
in effect for their respective source lineages.

## NAGISA v3 engine and evaluation assets

The public KifuLens source uses NAGISA v3 from the public `keinoda/YaneuraOu`
repository with iOS integration. Its evaluation assets and prebuilt iOS static
library are included for the default configuration.
The engine source is distributed under GNU GPL version 3.
The project owner holds the rights to the evaluation function and progress
coefficients and applies GNU GPL version 3 to them in this distribution.

- Public NAGISA v3 source:
  https://github.com/keinoda/YaneuraOu/tree/nagisa_v3
- NAGISA v3 engine edition:
  `YANEURAOU_ENGINE_SFNN_halfkahm2_1024_15_64_ls9`
- Source and license text:
  - `Vendor/NagisaV3Engine/Upstream`
  - `Vendor/NagisaV3Engine/Upstream/LICENSE`
- Evaluation assets:
  - NAGISA v3 `nn.bin`: 78,442,142 bytes,
    SHA-256 `e6b0b6ac99e95922ceba11633cc8e329968b152d7a79910156405f8a7ea9cdb9`
  - NAGISA v3 `progress.bin`: 1,003,104 bytes,
    SHA-256 `e7ed0eef88868335f9a46c58a121dccb5ad82a5eb1c8ee12de90365ab351e37d`

Each `progress.bin` is a required runtime asset. KifuLens checks the selected
engine's USI output for its successful load before starting analysis.

## New PetaShock opening book

KifuLens bundles the opening book published by the YaneuraOu project as
`new_petabook_20250505c.7z`. KifuLens converts `user_book1.db` to the formal
YaneuraOu YBB format, compresses it with LZFSE, extracts it once to
Application Support on first launch, and reuses the verified YBB afterward.
Opening-book queries read only the required positions rather than loading the
entire database into memory.

- Publisher: やねうらお (yaneurao)
- Project: YaneuraOu
- Release:
  https://github.com/yaneurao/YaneuraOu/releases/tag/new_petabook233
- Upstream release title: `新ペタショック定跡 233万局面`
- License: MIT License
- License basis: the official upstream release states that the opening book
  is published under the MIT License.
- Original archive:
  - Size: 76,080,406 bytes
  - SHA-256:
    `158a891fcb685af65a7d633541b5af57eb085422ff26372d53f6d92158031fb3`
- YBB conversion:
  - Converter:
    https://github.com/yaneurao/YaneuraOu-ScriptCollection/blob/70ee2f956f93da5a2c9e606ea94c05305bd85c8c/makebook/convert_db_to_ybb.py
  - Converter license: MIT License
  - Values are normalized to the YBB ranges: evaluation -32,000 through
    32,000 and depth 0 through 9,999.
- Bundled `user_book1.ybb.lzfse`:
  - Size: 85,263,832 bytes
  - SHA-256:
    `5ebf91f566e97084cc44dafbcda659eaa652862fd3cb8326aefb1cca831d66fa`
- Extracted `user_book1.ybb`:
  - Size: 195,680,126 bytes
  - SHA-256:
    `915d72caeeffc347ead41c67905f8bdd97218cdec883ee463012105e61af6d08`
  - Measured positions: 2,252,118
  - Measured moves: 16,097,817

“新ペタショック定跡 233万局面” is the upstream release title;
2,252,118 is the position count measured in the database bundled with
KifuLens. No separate copyright holder or copyright year was found in the
upstream release or distributed database. KifuLens therefore does not infer
one; the publisher, source, and upstream license declaration are recorded
above.

The MIT permission notice is included in `Docs/OpenSourceLicenses.md`.

## Licensed shogi piece artwork

KifuLens includes shogi piece artwork for which the project owner purchased
a product license from a third-party provider as `25667950.png`.

- Rights: the project owner purchased a product license to use this artwork.
- Source SHA-256:
  `9d0646aa7554b94a299bb7e171a69135cac1b025bef1dc8a27b757380f53955c`
- Processing: each piece is cropped from its original 162 × 180 px cell.
- The artwork is used as licensed, without redrawing or AI generation.
- Redistribution remains subject to the terms of the purchased license.

This artwork is not relicensed under MIT or GPL by this notice. Its use and
redistribution are governed by the license purchased by the project owner.

## ShogiHome board asset

KifuLens includes the `wood_warm.png` board texture from ShogiHome.

- Copyright (c) 2022 Kubo Ryosuke
- Project: https://github.com/sunfish-shogi/shogihome
- Source revision: `f07e934a270622ff7219f9dd94d490ba3098dd68`
- Original path: `public/board/wood_warm.png`
- SHA-256:
  `7e7088f7287c6bf4044af665dab62d1c2f0a0fa0fe44464695910729cbc073c4`
- License: MIT
- License text: `Vendor/ShogiHome/LICENSE`

At the cited revision, the file exists at the path above and is covered by
ShogiHome's root MIT License. The board PNG is included without modification.
KifuLens draws the board grid, coordinates, highlights, and surrounding
interface in SwiftUI.
