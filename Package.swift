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
    .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.3.5"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
]
products += [
    .executable(name: "Brief", targets: ["LocalDictation"]),
    .executable(name: "DictationWorker", targets: ["DictationWorker"])
]
targets += [
    .executableTarget(name: "LocalDictation", dependencies: ["DictationCore", .product(name: "Sparkle", package: "Sparkle")],
                      swiftSettings: [.swiftLanguageMode(.v5)],
                      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .executableTarget(name: "DictationWorker", dependencies: [
        "DictationCore",
        .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "MLX", package: "mlx-swift")
    ], swiftSettings: [.swiftLanguageMode(.v5)])
]
#endif
let package = Package(name: "Brief", platforms: [.macOS(.v14)],
                      products: products, dependencies: dependencies, targets: targets)
