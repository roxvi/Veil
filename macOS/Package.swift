// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "VeilNative",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "VeilNative", targets: ["VeilNative"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git",
                 revision: "4dcf5278fde40af60c36f667d8a472a90b38b247")
    ],
    targets: [
        .target(name: "VeilCore"),
        .executableTarget(name: "VeilNative", dependencies: ["VeilCore", "SwiftTerm"]),
        .testTarget(name: "VeilCoreTests", dependencies: ["VeilCore"]),
        .testTarget(name: "VeilEngineTests", dependencies: ["SwiftTerm"])
    ]
)
