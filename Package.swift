// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AudoCapture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AudoCaptureCore", targets: ["AudoCaptureCore"]),
        .executable(name: "AudoCaptureApp", targets: ["AudoCaptureApp"]),
        .executable(name: "AudoCaptureSmokeChecks", targets: ["AudoCaptureSmokeChecks"])
    ],
    targets: [
        .target(
            name: "AudoCaptureCore",
            path: "Sources/AudoCaptureCore"
        ),
        .executableTarget(
            name: "AudoCaptureApp",
            dependencies: ["AudoCaptureCore"],
            path: "Sources/AudoCaptureApp"
        ),
        .executableTarget(
            name: "AudoCaptureSmokeChecks",
            dependencies: ["AudoCaptureCore"],
            path: "Sources/AudoCaptureSmokeChecks"
        ),
        .testTarget(
            name: "AudoCaptureCoreTests",
            dependencies: ["AudoCaptureCore"],
            path: "Tests/AudoCaptureCoreTests"
        )
    ]
)
