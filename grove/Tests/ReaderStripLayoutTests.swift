import CoreGraphics
import Testing
@testable import grove

/// The reader strip's width ladder (`ReaderStripLayout`) and which controls
/// each rung seats on the strip versus folds into the `…` menu.
struct ReaderStripLayoutTests {
    typealias Tier = ReaderStripLayout.Tier
    typealias Control = ReaderStripLayout.Control

    // MARK: - Width → tier

    @Test(arguments: [
        (CGFloat(0), Tier.full),      // not yet measured: first pass renders full
        (CGFloat(-20), Tier.full),
        (CGFloat(0.5), Tier.minimal),
        (CGFloat(1), Tier.minimal),
        (CGFloat(479), Tier.minimal),
        (CGFloat(479.99), Tier.minimal),
        (CGFloat(480), Tier.compact),
        (CGFloat(480.01), Tier.compact),
        (CGFloat(619.99), Tier.compact),
        (CGFloat(620), Tier.full),
        (CGFloat(2000), Tier.full),
    ])
    func tierAtWidth(width: CGFloat, expected: Tier) {
        #expect(ReaderStripLayout.tier(forWidth: width) == expected)
    }

    @Test func thresholdsSitAt480And620() {
        #expect(ReaderStripLayout.minimalBelowWidth == 480)
        #expect(ReaderStripLayout.compactBelowWidth == 620)
    }

    @Test func narrowingNeverWidensTheTier() {
        func rank(_ tier: Tier) -> Int {
            switch tier {
            case .minimal: 0
            case .compact: 1
            case .full: 2
            }
        }
        var previous = rank(ReaderStripLayout.tier(forWidth: 1))
        for width in stride(from: CGFloat(1), through: 1200, by: 0.5) {
            let current = rank(ReaderStripLayout.tier(forWidth: width))
            #expect(current >= previous, "width \(width) dropped a tier")
            previous = current
        }
    }

    // MARK: - Tier → placement

    @Test func fullTierSeatsEverythingOnTheStrip() {
        for control in Control.allCases {
            #expect(ReaderStripLayout.isOnStrip(control, in: .full), "\(control)")
            #expect(!ReaderStripLayout.isFoldedIntoMenu(control, in: .full), "\(control)")
        }
    }

    @Test func compactTierFoldsReflectOpenInBrowserAndFullScreen() {
        let strip = Control.allCases.filter { ReaderStripLayout.isOnStrip($0, in: .compact) }
        let menu = Control.allCases.filter { ReaderStripLayout.isFoldedIntoMenu($0, in: .compact) }
        #expect(strip == [.overviewLabel, .sizeControls, .readerMode])
        #expect(menu == [.fullScreen, .reflect, .openInBrowser])
    }

    @Test func minimalTierKeepsOnlyTheWayOutAndTheMenu() {
        let strip = Control.allCases.filter { ReaderStripLayout.isOnStrip($0, in: .minimal) }
        let menu = Control.allCases.filter { ReaderStripLayout.isFoldedIntoMenu($0, in: .minimal) }
        #expect(strip.isEmpty)
        #expect(menu == [.fullScreen, .readerMode, .reflect, .openInBrowser])
    }

    /// Reflect, Open in Browser, Full Screen and Reader|Original must always be
    /// reachable exactly once: on the strip or in the menu, never both, never
    /// neither.
    @Test(arguments: [Control.fullScreen, .readerMode, .reflect, .openInBrowser])
    func actionControlsLiveInExactlyOnePlace(control: Control) {
        for tier in [Tier.full, .compact, .minimal] {
            let onStrip = ReaderStripLayout.isOnStrip(control, in: tier)
            let inMenu = ReaderStripLayout.isFoldedIntoMenu(control, in: tier)
            #expect(onStrip != inMenu, "\(control) at \(tier): strip \(onStrip), menu \(inMenu)")
        }
    }

    /// The Overview word simply goes (the chevron stays), and the size
    /// controls never need a stand-in because the menu always has them.
    @Test(arguments: [Control.overviewLabel, .sizeControls])
    func labelAndSizeControlsAreNeverFoldedIn(control: Control) {
        for tier in [Tier.full, .compact, .minimal] {
            #expect(!ReaderStripLayout.isFoldedIntoMenu(control, in: tier))
        }
        #expect(!ReaderStripLayout.isOnStrip(control, in: .minimal))
    }

    /// Text size and zoom outlast every other trailing control: whatever is
    /// still on the strip at a tier, the size controls are too.
    @Test func sizeControlsAreTheLastTrailingControlsToFold() {
        for tier in [Tier.full, .compact, .minimal] {
            let anyOtherOnStrip = Control.allCases
                .filter { $0 != .sizeControls && $0 != .overviewLabel }
                .contains { ReaderStripLayout.isOnStrip($0, in: tier) }
            if anyOtherOnStrip {
                #expect(ReaderStripLayout.isOnStrip(.sizeControls, in: tier), "\(tier)")
            }
        }
    }

    @Test func aControlSeatedWhenNarrowIsSeatedWhenWide() {
        for control in Control.allCases {
            if ReaderStripLayout.isOnStrip(control, in: .minimal) {
                #expect(ReaderStripLayout.isOnStrip(control, in: .compact))
            }
            if ReaderStripLayout.isOnStrip(control, in: .compact) {
                #expect(ReaderStripLayout.isOnStrip(control, in: .full))
            }
        }
    }
}
