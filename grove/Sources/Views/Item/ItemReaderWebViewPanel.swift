import SwiftUI

struct ItemReaderWebViewPanel: View {
    @Bindable var vm: ItemReaderViewModel
    let url: URL
    @Environment(\.openURL) private var openURL
    var focusTrigger: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Slim navigation bar
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { vm.showArticleWebView = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Overview")
                            .font(.groveMeta)
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 12)

                Text(url.host ?? url.absoluteString)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button {
                    vm.openReflectionEditor(type: .keyInsight, content: "", highlight: nil, focusTrigger: focusTrigger)
                } label: {
                    Label("Reflect", systemImage: "square.and.pencil")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Open reflection panel")

                Button {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    openURL(url)
                    #endif
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Open in Browser")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.bgCard)
            Divider()

            if vm.showFindBar {
                ItemReaderFindBar(vm: vm)
            }

            #if os(macOS)
            ArticleWebView(
                url: url,
                findQuery: vm.findQuery,
                findForwardToken: vm.findForwardToken,
                findBackwardToken: vm.findBackwardToken,
                onFindResult: { current, total in
                    vm.findCurrentMatch = current
                    vm.findMatchCount = total
                }
            )
            #else
            Text("Web view not yet available on iOS")
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
    }
}

// MARK: - Find Bar

struct ItemReaderFindBar: View {
    @Bindable var vm: ItemReaderViewModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                TextField("Find in article...", text: Binding(
                    get: { vm.findQuery },
                    set: { vm.findQuery = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.groveMeta)
                .onSubmit { vm.findForwardToken += 1 }
                #if os(macOS)
                .onExitCommand { vm.closeFindBar() }
                #endif
                if !vm.findQuery.isEmpty {
                    Text("\(vm.findCurrentMatch)/\(vm.findMatchCount)")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.bgCard)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )

            Button {
                vm.findBackwardToken += 1
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Previous match")
            .disabled(vm.findQuery.isEmpty)

            Button {
                vm.findForwardToken += 1
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Next match")
            .disabled(vm.findQuery.isEmpty)

            Button {
                vm.closeFindBar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Close find bar (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgCard)

        Divider()
    }
}
