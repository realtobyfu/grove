import UIKit
import SwiftData
import UniformTypeIdentifiers

/// Share Extension entry point.
///
/// Extracts a URL or plain text from the share sheet, saves it as an inbox
/// Item in the App Group shared ModelContainer, and dismisses. The full
/// SwiftUI ShareExtensionView (board picker, preview, notes) is wired in P2.3.
final class ShareViewController: UIViewController {

    private var modelContainer: ModelContainer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        do {
            modelContainer = try SharedModelContainer.makeForExtension()
        } catch {
            completeExtension()
            return
        }

        Task { @MainActor in
            await self.extractAndSave()
        }
    }

    // MARK: - Content Extraction

    /// Walks through shared NSExtensionItems, extracts the first URL or text,
    /// saves it to the shared store, and dismisses.
    private func extractAndSave() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeExtension()
            return
        }

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for provider in attachments {
                // Prefer URL attachments (web page shares)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let result = try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier
                    ) {
                        let urlString: String?
                        if let url = result as? URL {
                            urlString = url.absoluteString
                        } else if let string = result as? String {
                            urlString = string
                        } else {
                            urlString = nil
                        }

                        if let urlString {
                            let title = extensionItem.attributedContentText?.string
                            saveItem(urlString: urlString, title: title)
                            completeExtension()
                            return
                        }
                    }
                }

                // Fall back to plain text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let result = try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier
                    ),
                       let text = result as? String {
                        saveItem(urlString: text, title: nil)
                        completeExtension()
                        return
                    }
                }
            }
        }

        completeExtension()
    }

    // MARK: - Persistence

    /// Creates an Item in the shared ModelContainer. URL inputs become
    /// `.article` items; plain text becomes `.note` items. All start as `.inbox`.
    @MainActor
    private func saveItem(urlString: String, title: String?) {
        guard let container = modelContainer else { return }
        let context = container.mainContext

        let isURL = URL(string: urlString)?.scheme?.lowercased().hasPrefix("http") == true

        let item = Item(
            title: title ?? (isURL ? urlString : String(urlString.prefix(80))),
            type: isURL ? .article : .note
        )
        item.status = .inbox

        if isURL {
            item.sourceURL = urlString
        } else {
            item.content = urlString
        }

        context.insert(item)
        try? context.save()
    }

    // MARK: - Dismiss

    private func completeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
