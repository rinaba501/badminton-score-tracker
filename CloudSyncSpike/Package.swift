// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CloudSyncSpike",
    platforms: [
        .watchOS("11.0"),
        .iOS("17.0")
    ],
    products: [
        .library(name: "CloudSyncSpike", targets: ["CloudSyncSpike"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "CloudSyncSpike",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        )
    ]
)
