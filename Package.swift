// swift-tools-version: 6.2
import PackageDescription

// The persistence, recovery, vocabulary, audio and delivery-policy tests deliberately
// remain runnable without Apple frameworks or downloading model dependencies.
var dependencies: [Package.Dependency] = []
var products: [Product] = [.library(name: "DictationCore", targets: ["DictationCore"])]
var targets: [Target] = [
    .target(name: "DictationCore"),
    .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"])
]
#if os(macOS)
dependencies += [
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.1.5"),
    .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3")
]
products += [
    .executable(name: "Brief", targets: ["LocalDictation"]),
    .executable(name: "DictationWorker", targets: ["DictationWorker"])
]
targets += [
    .executableTarget(name: "LocalDictation", dependencies: ["DictationCore"],
                      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "DictationWorker", dependencies: [
        "DictationCore",
        .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
        .product(name: "MLX", package: "mlx-swift")
    ], swiftSettings: [.swiftLanguageMode(.v5)])
]
#endif
let package = Package(name: "Brief", platforms: [.macOS(.v14)],
                      products: products, dependencies: dependencies, targets: targets)
