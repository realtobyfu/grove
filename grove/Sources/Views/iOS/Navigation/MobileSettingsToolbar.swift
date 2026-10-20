import SwiftUI

/// One settings entry point shared by the mobile navigation roots.
private struct MobileSettingsToolbar: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { settingsButton }
                #else
                ToolbarItem(placement: .navigation) { settingsButton }
                #endif
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    MobileSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Settings")
        .keyboardShortcut(",", modifiers: .command)
    }
}

extension View {
    func mobileSettingsToolbar() -> some View {
        modifier(MobileSettingsToolbar())
    }
}
