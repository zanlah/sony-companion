// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonyCompanion",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SonyCompanion", targets: ["SonyCompanion"])],
    targets: [
        .target(name: "SonyProtocol"),
        .executableTarget(name: "SonyCompanion", dependencies: ["SonyProtocol"],
                          linkerSettings: [.linkedFramework("IOBluetooth")]),
        .testTarget(name: "SonyProtocolTests", dependencies: ["SonyProtocol"])
    ]
)
