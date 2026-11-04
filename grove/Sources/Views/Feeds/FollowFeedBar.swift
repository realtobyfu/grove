import SwiftUI

/// Inline follow input for the Following surface: paste a newspaper, blog,
/// or site URL and Grove discovers its feed, subscribes, and fetches the
/// first posts immediately. Mirrors the Home capture bar's field styling so
/// "paste a URL here" reads the same everywhere in the app.
struct FollowFeedBar: View {
    /// Opens the curated newsletter directory; the trailing shortcut is
    /// hidden when nil (e.g. compact placements).
    var onBrowseDirectory: (() -> Void)? = nil

    @State private var urlText = ""
    @State private var isValidating = false
    @State private var errorText: String?
    @State private var confirmationText: String?
    @State private var confirmationDismissTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                inputField

                if let onBrowseDirectory {
                    Button {
                        onBrowseDirectory()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "newspaper")
                                .font(.groveMeta)
                            Text("Directory")
                                .font(.groveBodySmall)
                        }
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
                    #if os(iOS)
                    .frame(minHeight: LayoutDimensions.minTouchTarget)
                    #endif
                    .help("Browse newsletters")
                    .accessibilityLabel("Browse directory")
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: errorText)
    }

    // MARK: - Input Field

    private var inputField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "link")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 16)

            TextField("", text: $urlText, prompt:
                Text("Paste a site or feed URL")
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.groveBody)
            .foregroundStyle(Color.textPrimary)
            .focused($isFocused)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .onSubmit { follow() }
            .onChange(of: urlText) { _, _ in
                errorText = nil
            }

            if isValidating {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finding feed")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
            } else if !trimmedURL.isEmpty {
                Button {
                    follow()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Follow this site")
                .accessibilityHint("Finds the site's feed and subscribes.")
            }

            Text("⏎")
                .font(.groveShortcut)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.borderPrimary : Color.borderInput, lineWidth: 1)
        )
        .overlay {
            if let confirmationText {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                    Text(confirmationText)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.bgCard)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    // MARK: - Follow

    private func follow() {
        let trimmed = trimmedURL
        guard !trimmed.isEmpty, !isValidating else { return }

        isValidating = true
        errorText = nil

        Task {
            defer { isValidating = false }
            switch await FeedSubscriptionService.validateAndAdd(urlString: trimmed) {
            case .success(let source):
                urlText = ""
                showConfirmation("Following \(source.title ?? source.domain)")
                // Fetch right away so the first posts appear without waiting
                // for the next background refresh cycle.
                await FeedFetchService.shared.fetchNow(source.id)
            case .failure(let error):
                errorText = error.errorDescription
            }
        }
    }

    private func showConfirmation(_ message: String) {
        confirmationDismissTask?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            confirmationText = message
        }
        confirmationDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                confirmationText = nil
            }
        }
    }
}
