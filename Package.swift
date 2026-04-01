// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StarMate",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "StarMate",
            targets: ["StarMate"]),
    ],
    targets: [
        .target(
            name: "StarMate",
            path: "Sources"),
    ]
)
