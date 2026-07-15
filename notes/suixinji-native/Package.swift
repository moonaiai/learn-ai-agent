// swift-tools-version:5.9
import PackageDescription
import Foundation

var webEditorExcludes = [
    "WebEditor/src",
    "WebEditor/package.json",
    "WebEditor/package-lock.json"
]
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let webNodeModules = packageRoot
    .appendingPathComponent("Sources/Suixinji/WebEditor/node_modules")
    .path
if FileManager.default.fileExists(atPath: webNodeModules) {
    webEditorExcludes.append("WebEditor/node_modules")
}

let package = Package(
    name: "Suixinji",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "Suixinji",
            path: "Sources/Suixinji",
            exclude: webEditorExcludes,
            resources: [
                .copy("WebEditor/dist")
            ]
        )
    ]
)
