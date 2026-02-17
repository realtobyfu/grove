import SwiftUI

/// Settings view for configuring AI synthesis behavior.
struct AISettingsView: View {
    @State private var provider = SynthesisSettings.provider
    @State private var apiEndpoint = SynthesisSettings.apiEndpoint
    @State private var apiKey = SynthesisSettings.apiKey
    @State private var apiModel = SynthesisSettings.apiModel

    var body: some View {
        Form {
            Section("Synthesis Provider") {
                Picker("Provider", selection: $provider) {
                    ForEach(SynthesisProvider.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .onChange(of: provider) { _, newValue in
                    SynthesisSettings.provider = newValue
                }

                switch provider {
                case .local:
                    Text("Uses keyword extraction and heuristics to generate synthesis notes locally. No data leaves your machine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .api:
                    Text("Sends item content to an OpenAI-compatible API for higher-quality synthesis. Requires an API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if provider == .api {
                Section("API Configuration") {
                    TextField("API Endpoint", text: $apiEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiEndpoint) { _, newValue in
                            SynthesisSettings.apiEndpoint = newValue
                        }
                    Text("Default: https://api.openai.com/v1/chat/completions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            SynthesisSettings.apiKey = newValue
                        }

                    TextField("Model", text: $apiModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiModel) { _, newValue in
                            SynthesisSettings.apiModel = newValue
                        }
                    Text("e.g., gpt-4o-mini, gpt-4o, claude-3-haiku-20240307")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Synthesis generates a summary note that highlights key themes, contradictions, and open questions across items in a board or tag cluster.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Generated notes are explicitly marked as AI-generated and can be freely edited after creation. All source items are linked via connections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Synthesis works best with 3–15 items. Larger scopes may produce less focused results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }
}
