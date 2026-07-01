import SwiftUI

struct WidgetPreviewPanel: View {
    var snapshot: WidgetSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            previewRow
            previewStack
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewRow: some View {
        HStack(alignment: .top, spacing: 14) {
            smallPreview
            mediumPreview
            largePreview
        }
    }

    private var previewStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            smallPreview
            mediumPreview
            largePreview
        }
    }

    private var smallPreview: some View {
        WidgetPreviewTile(title: "小尺寸", size: CGSize(width: 132, height: 136)) {
            ScaledWidgetPreview(baseSize: CGSize(width: 158, height: 158), scale: 0.68) {
                SmallSignInWidgetView(snapshot: snapshot, isInteractive: false)
            }
        }
    }

    private var mediumPreview: some View {
        WidgetPreviewTile(title: "中尺寸", size: CGSize(width: 220, height: 136)) {
            ScaledWidgetPreview(baseSize: CGSize(width: 338, height: 158), scale: 0.58) {
                MediumGachaWidgetView(snapshot: snapshot, isInteractive: false)
            }
        }
    }

    private var largePreview: some View {
        WidgetPreviewTile(title: "大尺寸", size: CGSize(width: 168, height: 176)) {
            ScaledWidgetPreview(baseSize: CGSize(width: 338, height: 354), scale: 0.42) {
                LargeToolboxWidgetView(snapshot: snapshot, isInteractive: false)
            }
        }
    }
}

private struct WidgetPreviewTile<Content: View>: View {
    var title: String
    var size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)

                content
                    .compositingGroup()
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .frame(alignment: .topLeading)
    }
}

private struct ScaledWidgetPreview<Content: View>: View {
    var baseSize: CGSize
    var scale: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scaleEffect(scale)
            .frame(
                width: baseSize.width * scale,
                height: baseSize.height * scale
            )
    }
}

#Preview {
    WidgetPreviewPanel(snapshot: .empty)
        .padding()
        .frame(width: 520)
}
