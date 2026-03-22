// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ezmdv",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "EzmdvCore"
        ),
        .executableTarget(
            name: "EzmdvApp",
            dependencies: ["EzmdvCore"],
            resources: [
                .copy("Resources/markdown.html"),
                .copy("Resources/markdown.css"),
                .copy("Resources/editor.js"),
                .copy("Resources/marked.min.js"),
            ]
        ),
        .testTarget(
            name: "EzmdvTests",
            dependencies: ["EzmdvCore"]
        ),
    ]
)
