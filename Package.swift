// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nopingy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "nopingy", targets: ["Nopingy"]),
        .executable(name: "nopingy-checks", targets: ["NopingyChecks"])
    ],
    targets: [
        .target(name: "NopingyCore"),
        .executableTarget(name: "Nopingy", dependencies: ["NopingyCore"]),
        .executableTarget(name: "NopingyChecks", dependencies: ["NopingyCore"], path: "Tests/NopingyCoreTests")
    ]
)
