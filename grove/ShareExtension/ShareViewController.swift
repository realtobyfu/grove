import UIKit
import SwiftUI
import SQLiteData
import UniformTypeIdentifiers

/// Share Extension entry point.
///
/// Extracts a URL or plain text from the share sheet, then presents
/// ShareExtensionView — a SwiftUI form with title/domain preview,
/// board picker, and optional note — for the user to review before saving.
final class ShareViewController: UIViewController {

    /// An extension process can load this controller more than once, and the
    /// default database can be set only once. This turns true only when the library
    /// has opened: until then nothing has read the database, and Grove may have
    /// created the file since the last try.
    private static var isDatabasePrepared = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        do {
            guard try Self.prepareDatabase() else {
                presentOpenGroveFirst()
                return
            }
        } catch {
            completeExtension()
            return
        }

        Task { @MainActor in
            await self.extractAndPresent()
        }
    }

    /// Returns `false` if Grove has not created the library yet. The extension must
    /// never create it: Grove imports the SwiftData library only while the file
    /// doesn't exist, so a file made here would abandon that library.
    private static func prepareDatabase() throws -> Bool {
        guard !isDatabasePrepared else { return true }
        guard let database = try AppDatabase.openExistingForExtension() else { return false }
        prepareDependencies { $0.defaultDatabase = database }
        isDatabasePrepared = true
        return true
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
        embed(ShareExtensionView(
            sharedURL: url,
            sharedTitle: title,
            onComplete: { [weak self] in
                self?.completeExtension()
            }
        ))
    }

    /// Must not touch the database: it was never set up for this view.
    @MainActor
    private func presentOpenGroveFirst() {
        embed(ShareOpenGroveFirstView(onDone: { [weak self] in
            self?.completeExtension()
        }))
    }

    @MainActor
    private func embed(_ rootView: some View) {
        let hostingController = UIHostingController(rootView: rootView)
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
