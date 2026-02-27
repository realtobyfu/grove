#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Settings view for sending feedback via email.
struct FeedbackSettingsView: View {
    var body: some View {
        Form {
            Section("Feedback") {
                Button("Send Feedback") {
                    let subject = "Grove Feedback"
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Grove%20Feedback"
                    if let url = URL(string: "mailto:3tobiasfu@gmail.com?subject=\(subject)") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                .buttonStyle(.borderedProminent)

                Text("Opens your default email client with a pre-filled message to the developer.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }
}
