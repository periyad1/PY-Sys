// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PYSys",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PYSys",
            path: "Sources/PYSys",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("SystemConfiguration"),
            ]
        )
    ]
)
