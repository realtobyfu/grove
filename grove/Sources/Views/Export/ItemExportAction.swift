import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Item Export Action

/// Runs the export flow directly: save panel, then write. There is deliberately
/// no interstitial sheet — "Export" is a single verb, and the save panel is
/// already the place where the user picks a name and confirms.
///
/// iOS has no export entry point today, so the call is a no-op there.
@MainActor
enum ItemExportAction {

    static func exportAsMarkdown(_ item: ItemGraph) {
        #if os(macOS)
        guard let url = ExportService.showSavePanel(filename: item.title) else { return }
        guard let data = ExportService.exportItem(item) else {
            presentFailure(message: "Grove couldn't generate Markdown for \"\(item.title)\".")
            return
        }
        do {
            try data.write(to: url)
        } catch {
            presentFailure(message: error.localizedDescription)
        }
        #endif
    }

    #if os(macOS)
    private static func presentFailure(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    #endif
}
