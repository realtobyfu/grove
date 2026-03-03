import Foundation
import Testing
@testable import grove

struct ResizablePaneTests {
    @Test func trailingPaneResizeMathIncreasesWidthWhenDraggingLeft() {
        let nextWidth = TrailingPaneResizeMath.nextWidth(
            initialWidth: 360,
            dragTranslationX: -40,
            minWidth: 280,
            maxWidth: 520
        )

        #expect(nextWidth == 400)
    }

    @Test func trailingPaneResizeMathDecreasesWidthWhenDraggingRight() {
        let nextWidth = TrailingPaneResizeMath.nextWidth(
            initialWidth: 360,
            dragTranslationX: 40,
            minWidth: 280,
            maxWidth: 520
        )

        #expect(nextWidth == 320)
    }

    @Test func trailingPaneResizeMathClampsAtMinimumWidth() {
        let nextWidth = TrailingPaneResizeMath.nextWidth(
            initialWidth: 320,
            dragTranslationX: 100,
            minWidth: 280,
            maxWidth: 520
        )

        #expect(nextWidth == 280)
    }

    @Test func trailingPaneResizeMathClampsAtMaximumWidth() {
        let nextWidth = TrailingPaneResizeMath.nextWidth(
            initialWidth: 480,
            dragTranslationX: -100,
            minWidth: 280,
            maxWidth: 520
        )

        #expect(nextWidth == 520)
    }

    @Test func trailingPaneResizeMathDoesNotCollapseAtMinimumWidth() {
        let shouldCollapse = TrailingPaneResizeMath.shouldCollapse(
            initialWidth: 380,
            dragTranslationX: 100,
            predictedEndTranslationX: 100,
            minWidth: 280,
            collapseOvershoot: TrailingPaneResizeMath.defaultCollapseOvershoot
        )

        #expect(!shouldCollapse)
    }

    @Test func trailingPaneResizeMathCollapsesAfterOvershootingMinimumWidth() {
        let shouldCollapse = TrailingPaneResizeMath.shouldCollapse(
            initialWidth: 380,
            dragTranslationX: 180,
            predictedEndTranslationX: 180,
            minWidth: 280,
            collapseOvershoot: TrailingPaneResizeMath.defaultCollapseOvershoot
        )

        #expect(shouldCollapse)
    }

    @Test func trailingPaneResizeMathUsesPredictedEndTranslationForCollapse() {
        let shouldCollapse = TrailingPaneResizeMath.shouldCollapse(
            initialWidth: 380,
            dragTranslationX: 120,
            predictedEndTranslationX: 180,
            minWidth: 280,
            collapseOvershoot: TrailingPaneResizeMath.defaultCollapseOvershoot
        )

        #expect(shouldCollapse)
    }

    @Test func layoutSettingsReturnsNilForUnsetWidth() {
        let defaults = UserDefaults.standard
        let key = LayoutSettings.PaneWidthKey.contentWrite
        let originalValue = defaults.object(forKey: key.rawValue)

        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key.rawValue)
            } else {
                defaults.removeObject(forKey: key.rawValue)
            }
        }

        defaults.removeObject(forKey: key.rawValue)

        #expect(LayoutSettings.width(for: key) == nil)
    }

    @Test func layoutSettingsRoundTripsStoredWidth() {
        let defaults = UserDefaults.standard
        let key = LayoutSettings.PaneWidthKey.boardPrompt
        let originalValue = defaults.object(forKey: key.rawValue)

        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key.rawValue)
            } else {
                defaults.removeObject(forKey: key.rawValue)
            }
        }

        LayoutSettings.setWidth(412, for: key)

        #expect(LayoutSettings.width(for: key) == 412)
        #expect(defaults.object(forKey: key.rawValue) as? Double == 412)
    }
}
