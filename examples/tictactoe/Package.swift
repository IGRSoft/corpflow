// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TicTacToe",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "TicTacToeKit", targets: ["TicTacToeKit"]),
        .executable(name: "tictactoe", targets: ["tictactoe"]),
    ],
    targets: [
        .target(
            name: "TicTacToeKit"
        ),
        .executableTarget(
            name: "tictactoe",
            dependencies: ["TicTacToeKit"]
        ),
        .testTarget(
            name: "TicTacToeKitTests",
            dependencies: ["TicTacToeKit"]
        ),
    ]
)
