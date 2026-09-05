// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KifuLensEngine",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "KifuLensEngine",
            targets: ["KifuLensEngine"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "KifuLensNative",
            path: "Frameworks/KifuLensNative.xcframework"
        ),
        .target(
            name: "KifuLensEngine",
            dependencies: ["KifuLensNative"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
