import ProjectDescription

let project = Project(
    name: "grove",
    targets: [
        .target(
            name: "grove",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.grove",
            infoPlist: .default,
            buildableFolders: [
                "grove/Sources",
                "grove/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "groveTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.groveTests",
            infoPlist: .default,
            buildableFolders: [
                "grove/Tests"
            ],
            dependencies: [.target(name: "grove")]
        ),
    ]
)
