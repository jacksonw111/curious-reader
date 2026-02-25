import SwiftUI

struct ReaderSettingsSheet: View {
    @ObservedObject var model: ReaderWorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var saveHint: String?
    private let accent = Color(red: 0.43, green: 0.30, blue: 0.18)

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    Picker(
                        "EPUB Font",
                        selection: Binding(
                            get: { model.preferences.epubFontStyle },
                            set: { model.updateEPUBFontStyle($0) }
                        )
                    ) {
                        ForEach(ReaderFontStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    HStack {
                        Text("Font Size")
                        Slider(
                            value: Binding(
                                get: { model.preferences.epubFontSize },
                                set: { model.updateEPUBFontSize($0) }
                            ),
                            in: 14...30,
                            step: 1
                        )
                        Text("\(Int(model.preferences.epubFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                Section("Translation") {
                    Text("Curious Reader automatically selects an OpenRouter free model.")
                        .foregroundStyle(.secondary)
                    SecureField("OpenRouter API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save Key") {
                            model.saveOpenRouterAPIKey(apiKeyInput)
                            apiKeyInput = ""
                            saveHint = "API key saved to Keychain."
                        }
                        Button("Remove Key", role: .destructive) {
                            model.removeOpenRouterAPIKey()
                            saveHint = "API key removed."
                        }
                        Spacer()
                        Text(model.hasOpenRouterAPIKey ? "Configured" : "Missing")
                            .foregroundStyle(model.hasOpenRouterAPIKey ? accent : .secondary)
                    }
                }

                if let saveHint {
                    Section {
                        Text(saveHint)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.93, blue: 0.85),
                        Color(red: 0.92, green: 0.88, blue: 0.79),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .tint(accent)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
