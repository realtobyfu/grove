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
                // Tuist's default Info.plist hardcodes 1.0/1 and ignores the
                // version build settings, so these must be wired up explicitly
                // or every release ships as 1.0 (1).
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // Grove only uses HTTPS, which is exempt. Without this key every
                // upload stalls in App Store Connect waiting on a manual answer.
                "ITSAppUsesNonExemptEncryption": false,
                "CFBundleURLTypes": [
                    [
                        "CFBundleTypeRole": "Editor",
                        "CFBundleURLName": "dev.tuist.grove",
                        "CFBundleURLSchemes": ["grove"],
                    ],
                ],
                "UILaunchScreen": [
                    "UIColorName": "bgPrimary",
                ],
                "UIBackgroundModes": [
                    "remote-notification",
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
                // iOS ships as 1.0; the macOS app is on 2.x. The share
                // extension below must always match this target exactly.
                "MARKETING_VERSION": "1.0",
                "CURRENT_PROJECT_VERSION": "5",
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
                // Must match the host app exactly or App Store validation fails.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
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
                "MARKETING_VERSION": "1.0",
                "CURRENT_PROJECT_VERSION": "5",
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
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // See the iOS target: HTTPS-only, exempt, must be declared or the
                // upload stalls awaiting a manual answer.
                "ITSAppUsesNonExemptEncryption": false,
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
                // Required, and required to stay "Apple Development": Tuist defaults
                // macOS to ad-hoc signing ("-"), which the iCloud and push entitlements
                // reject. Automatic signing then substitutes the distribution cert at
                // export time — setting "Apple Distribution" here instead is a
                // conflicting-provisioning error, not an upgrade.
                "CODE_SIGN_IDENTITY[sdk=macosx*]": "Apple Development",
                "DEVELOPMENT_TEAM": "679K683SQ5",
                "MARKETING_VERSION": "2.0.0",
                "CURRENT_PROJECT_VERSION": "5",
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
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
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
