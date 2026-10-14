// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Apollo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Apollo", targets: ["Apollo"])],
    targets: [
        .target(name: "ApolloCore"),
        .executableTarget(
            name: "Apollo",
            dependencies: ["ApolloCore"]
        ),
        .testTarget(name: "ApolloCoreTests", dependencies: ["ApolloCore"])
    ]
)
