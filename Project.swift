import ProjectDescription

let project = Project(
    name: "grove",
    targets: [
        // MARK: - grove-ios (iPhone + iPad)
        .target(
            name: "grove-ios",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "dev.tuist.grove",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Grove",
                "CFBundleName": "Grove",
                "CFBundleIconName": "AppIcon",
                "UILaunchScreen": [
                    "UIColorName": "bgPrimary",
                ],
                "UIAppFonts": [
                    "IBMPlexMono-Medium.ttf",
                    "IBMPlexMono-Regular.ttf",
                    "IBMPlexMono-SemiBold.ttf",
                    "IBMPlexSans-Light.ttf",
                    "IBMPlexSans-Medium.ttf",
                    "IBMPlexSans-Regular.ttf",
                    "Newsreader-Italic.ttf",
                    "Newsreader-Medium.ttf",
                    "Newsreader-MediumItalic.ttf",
                    "Newsreader-Regular.ttf",
                    "Newsreader-SemiBold.ttf",
                    "Newsreader-SemiBoldItalic.ttf",
                ],
            ]),
            buildableFolders: [
                "grove/Sources",
                "grove/Resources",
            ],
            entitlements: .file(path: "grove/grove-ios.entitlements"),
            dependencies: [.target(name: "GroveShareExtension")],
            settings: .settings(base: [
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_VERSION": "6.0",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "679K683SQ5",
                "MARKETING_VERSION": "1.0.0",
                "CURRENT_PROJECT_VERSION": "1",
            ])
        ),
        // MARK: - GroveShareExtension (iOS Share Extension)
        .target(
            name: "GroveShareExtension",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "dev.tuist.grove.share-extension",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Save to Grove",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionActivationRule": [
                        "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                        "NSExtensionActivationSupportsText": true,
                    ],
                ],
            ]),
            buildableFolders: [
                "grove/Sources",
                "grove/ShareExtension",
                "grove/Resources",
            ],
            entitlements: .file(path: "grove/share-extension.entitlements"),
            dependencies: [],
            settings: .settings(base: [
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_VERSION": "6.0",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "SHARE_EXTENSION",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "679K683SQ5",
                "MARKETING_VERSION": "1.0.0",
                "CURRENT_PROJECT_VERSION": "1",
            ])
        ),
        // MARK: - grove (macOS)
        .target(
            name: "grove",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.grove",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Grove",
                "CFBundleName": "Grove",
                "CFBundleIconName": "AppIcon",
                "ATSApplicationFontsPath": "Fonts",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "NSMainStoryboardFile": "",
                "NSPrincipalClass": "NSApplication",
            ]),
            buildableFolders: [
                "grove/Sources",
                "grove/Resources",
            ],
            entitlements: .file(path: "grove/grove.entitlements"),
            dependencies: [],
            settings: .settings(base: [
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_VERSION": "6.0",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "CODE_SIGN_STYLE": "Automatic",
                "CODE_SIGN_IDENTITY[sdk=macosx*]": "Apple Development",
                "DEVELOPMENT_TEAM": "679K683SQ5",
                "MARKETING_VERSION": "1.0.0",
                "CURRENT_PROJECT_VERSION": "1",
            ])
        ),
        .target(
            name: "grove-demo",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.grove.demo",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Grove Demo",
                "CFBundleName": "Grove Demo",
                "CFBundleIconName": "AppIcon",
                "ATSApplicationFontsPath": "Fonts",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "NSMainStoryboardFile": "",
                "NSPrincipalClass": "NSApplication",
            ]),
            buildableFolders: [
                "grove/Sources",
                "grove/Resources",
            ],
            entitlements: .file(path: "grove/groveDemo.entitlements"),
            dependencies: [],
            settings: .settings(base: [
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_VERSION": "6.0",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "CODE_SIGN_STYLE": "Automatic",
                "CODE_SIGN_IDENTITY[sdk=macosx*]": "Apple Development",
                "DEVELOPMENT_TEAM": "679K683SQ5",
                "MARKETING_VERSION": "1.0.0",
                "CURRENT_PROJECT_VERSION": "1",
            ])
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
            dependencies: [.target(name: "grove")],
            settings: .settings(base: [
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_VERSION": "6.2",
            ])
        ),
    ]
)
