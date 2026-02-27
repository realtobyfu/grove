import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Share Extension entry point.
///
/// Extracts a URL or plain text from the share sheet, then presents
/// ShareExtensionView — a SwiftUI form with title/domain preview,
/// board picker, and optional note — for the user to review before saving.
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
            await self.extractAndPresent()
        }
    }

    // MARK: - Content Extraction

    /// Walks through shared NSExtensionItems, extracts the first URL or text,
    /// then presents the SwiftUI share view for user confirmation.
    private func extractAndPresent() async {
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
                            presentShareView(url: urlString, title: title)
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
                        presentShareView(url: text, title: nil)
                        return
                    }
                }
            }
        }

        completeExtension()
    }

    // MARK: - Present SwiftUI View

    @MainActor
    private func presentShareView(url: String, title: String?) {
        guard let container = modelContainer else {
            completeExtension()
            return
        }

        let shareView = ShareExtensionView(
            sharedURL: url,
            sharedTitle: title,
            onComplete: { [weak self] in
                self?.completeExtension()
            }
        )
        .modelContainer(container)

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.didMove(toParent: self)
    }

    // MARK: - Dismiss

    private func completeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
