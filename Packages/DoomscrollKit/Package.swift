// swift-tools-version:6.0
// Code shared by the app and its two Screen Time extensions. Foundation and SwiftUI only, so the
// monitor extension (6 MB memory limit) stays small and the logic is testable with `swift test` on a Mac.
import PackageDescription

let package = Package(
    name: "DoomscrollKit",
    platforms: [.iOS("17.4"), .macOS(.v14)],
    products: [.library(name: "DoomscrollKit", targets: ["DoomscrollKit"])],
    targets: [
        .target(name: "DoomscrollKit"),
        .testTarget(name: "DoomscrollKitTests", dependencies: ["DoomscrollKit"]),
    ]
)
