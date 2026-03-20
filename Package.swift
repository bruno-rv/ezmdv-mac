// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ezmdv",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EzmdvApp",
            resources: [
                .copy("Resources/markdown.html"),
                .copy("Resources/markdown.css"),
                .copy("Resources/editor.js"),
            ]
        ),
    ]
)
