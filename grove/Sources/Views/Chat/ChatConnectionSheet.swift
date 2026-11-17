import SwiftUI
import SwiftData

/// Sheet for creating a connection between two items referenced in a chat message.
struct ChatConnectionSheet: View {
    let message: ChatMessage
    let referencedItems: [Item]
    @Binding var connectionType: ConnectionType
    var onCreateConnection: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Create Connection")
                .font(.groveItemTitle)

            if referencedItems.count >= 2 {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("From:")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textMuted)
                    Text(referencedItems[0].title)
                        .font(.groveBody)

                    Text("To:")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textMuted)
                    Text(referencedItems[1].title)
                        .font(.groveBody)

                    Picker("Type", selection: $connectionType) {
                        ForEach(ConnectionType.userSelectableCases, id: \.self) { type in
                            Text(type.displayLabel).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .buttonStyle(.grove(.secondary))

                    Button("Create") {
                        onCreateConnection()
                    }
                    .buttonStyle(.grove(.primary))
                }
            } else {
                Text("Need at least 2 referenced items to create a connection.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)

                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.grove(.secondary))
            }
        }
        .padding(Spacing.xl)
        .frame(width: 350)
    }
}
