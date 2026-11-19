// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "TN3270Core", targets: ["TN3270Core"]),
]

var targets: [Target] = [
    .target(name: "TN3270Core"),
    .testTarget(name: "TN3270CoreTests", dependencies: ["TN3270Core"]),
]

#if os(macOS)
// The SwiftUI front end is only available on macOS. The protocol engine in
// TN3270Core is platform independent so it can be unit tested anywhere.
products.append(.executable(name: "TN3270Mac", targets: ["TN3270Mac"]))
targets.append(.executableTarget(name: "TN3270Mac", dependencies: ["TN3270Core"]))
targets.append(.testTarget(name: "TN3270MacTests", dependencies: ["TN3270Mac"]))
#endif

let package = Package(
    name: "TN3270Mac",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
