import SwiftUI

struct MetadataArtworkView: View {
    let url: URL?
    let title: String
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(3)
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary)
        }
        .accessibilityLabel(title)
    }

    private var fallback: some View {
        Text(String(title.prefix(1)))
            .font(.system(size: max(size * 0.38, 12), weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
