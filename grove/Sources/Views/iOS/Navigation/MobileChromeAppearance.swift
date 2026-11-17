#if os(iOS) && !SHARE_EXTENSION
import SwiftUI
import UIKit

/// UIKit appearance for the chrome SwiftUI doesn't expose: Newsreader
/// navigation titles and an ink tab-bar badge in place of system red.
/// Only fonts and badge colours change; bar backgrounds keep the system
/// default for each slot. Applied once at startup from `MobileRootView`.
@MainActor
enum MobileChromeAppearance {
    private static var isApplied = false

    static func apply() {
        guard !isApplied else { return }
        isApplied = true
        applyNavigationBar()
        applyTabBarBadge()
    }

    private static var ink: UIColor {
        UIColor(named: "textPrimary") ?? UIColor(Color.textPrimary)
    }

    private static var inverseInk: UIColor {
        UIColor(named: "textInverse") ?? UIColor(Color.textInverse)
    }

    private static func newsreader(size: CGFloat, textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: "Newsreader-Medium", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: textStyle == .largeTitle ? .bold : .semibold)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }

    // MARK: - Navigation bar

    private static func applyNavigationBar() {
        let largeTitle: [NSAttributedString.Key: Any] = [
            .font: newsreader(size: 34, textStyle: .largeTitle),
            .foregroundColor: ink,
        ]
        let inlineTitle: [NSAttributedString.Key: Any] = [
            .font: newsreader(size: 17, textStyle: .headline),
            .foregroundColor: ink,
        ]

        func styled(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
            appearance.largeTitleTextAttributes = largeTitle
            appearance.titleTextAttributes = inlineTitle
            return appearance
        }

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let compact = UINavigationBarAppearance()
        compact.configureWithDefaultBackground()
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = styled(standard)
        proxy.compactAppearance = styled(compact)
        proxy.scrollEdgeAppearance = styled(scrollEdge)
        proxy.compactScrollEdgeAppearance = styled({
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            return appearance
        }())
    }

    // MARK: - Tab bar badge

    private static func applyTabBarBadge() {
        let badgeText: [NSAttributedString.Key: Any] = [.foregroundColor: inverseInk]

        func inkBadge(_ item: UITabBarItemAppearance) {
            for state in [item.normal, item.selected, item.focused, item.disabled] {
                state.badgeBackgroundColor = ink
                state.badgeTextAttributes = badgeText
            }
        }

        // Starts from the system default background, so only the badge changes.
        // The scroll-edge slot is left unset: UIKit derives it from the
        // standard appearance, badge colours included.
        let standard = UITabBarAppearance()
        standard.configureWithDefaultBackground()
        inkBadge(standard.stackedLayoutAppearance)
        inkBadge(standard.inlineLayoutAppearance)
        inkBadge(standard.compactInlineLayoutAppearance)
        UITabBar.appearance().standardAppearance = standard
    }
}
#endif
