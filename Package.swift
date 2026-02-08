// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Launchpick",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Launchpick",
            path: "Sources/Launchpick",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ]
)
