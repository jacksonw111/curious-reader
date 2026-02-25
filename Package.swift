// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CuriousReader",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "ReaderPDF", targets: ["ReaderPDF"]),
        .library(name: "ReaderEPUB", targets: ["ReaderEPUB"]),
        .library(name: "ReaderMOBI", targets: ["ReaderMOBI"]),
        .library(name: "ReaderLibrary", targets: ["ReaderLibrary"]),
        .executable(name: "CuriousReaderApp", targets: ["CuriousReaderApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "ReaderCore"),
        .target(
            name: "ReaderPDF",
            dependencies: ["ReaderCore"]
        ),
        .target(
            name: "ReaderEPUB",
            dependencies: [
                "ReaderCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .target(
            name: "ReaderMOBI",
            dependencies: ["ReaderCore", "ReaderEPUB"]
        ),
        .target(
            name: "ReaderLibrary",
            dependencies: ["ReaderCore"]
        ),
        .executableTarget(
            name: "CuriousReaderApp",
            dependencies: ["ReaderCore", "ReaderPDF", "ReaderEPUB", "ReaderMOBI", "ReaderLibrary"]
        ),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: ["ReaderCore"]
        ),
        .testTarget(
            name: "ReaderMOBITests",
            dependencies: ["ReaderMOBI"]
        ),
        .testTarget(
            name: "ReaderEPUBTests",
            dependencies: [
                "ReaderEPUB",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "ReaderLibraryTests",
            dependencies: ["ReaderLibrary"]
        ),
        .testTarget(
            name: "ReaderPDFTests",
            dependencies: ["ReaderPDF"]
        ),
        .testTarget(
            name: "CuriousReaderAppTests",
            dependencies: ["CuriousReaderApp"]
        ),
    ]
)
