// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BiliAccelerator",
    platforms: [.tvOS(.v16), .iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "BiliAccelerator", targets: ["BiliAccelerator"]),
    ],
    targets: [
        .target(name: "BiliAccelerator"),
        .testTarget(name: "BiliAcceleratorTests", dependencies: ["BiliAccelerator"]),
    ]
)
