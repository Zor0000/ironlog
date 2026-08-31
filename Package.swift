// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IronLog",
    platforms: [.iOS(.v17)],
    products: [
        .executableTarget(name: "IronLog"),
    ],
    dependencies: [
        .package(url: "https://github.com/ParthJadhav/liveline-swift.git", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "IronLog",
            dependencies: ["Liveline"],
            path: "IronLog"
        ),
    ]
)