import SwiftUI

struct TranslationPanelView: View {
    let state: TranslationPanelState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if state.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(state.isStreaming ? "Translating" : "Translation")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            } else if state.translatedText.isEmpty {
                Text(state.isStreaming ? "Translating..." : "No translation.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(state.translatedText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 170)
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
        )
    }
}
