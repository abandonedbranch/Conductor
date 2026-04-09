import SwiftUI

struct WebReaderCardView: View {
    let status: WebReaderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .loading(let url):
                Label {
                    Text("Reading page…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

            case .success(let result):
                Label(result.title.isEmpty ? "Page loaded" : result.title, systemImage: "globe")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(result.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(result.text.count) characters extracted")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

            case .error(let description):
                Label("Failed to read page", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
