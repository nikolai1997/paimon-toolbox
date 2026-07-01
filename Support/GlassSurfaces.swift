import SwiftUI

struct AppGlassBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)

            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.70),
                    Color.accentColor.opacity(0.10),
                    Color.mint.opacity(0.07),
                    Color.orange.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.72)
        }
        .ignoresSafeArea()
    }
}

struct GlassSection<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .glassPanel(cornerRadius: cornerRadius)
    }
}

struct GlassMetricCard: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 128, maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 16)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.46),
                                .white.opacity(0.12),
                                .black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .glassHoverGlow(cornerRadius: cornerRadius)
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    func glassHoverGlow(cornerRadius: CGFloat) -> some View {
        modifier(GlassHoverGlowModifier(cornerRadius: cornerRadius))
    }

    func glassPagePadding() -> some View {
        padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
    }

    func softSeparator() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 1)
        }
    }
}

struct GlassHoverGlowModifier: ViewModifier {
    let cornerRadius: CGFloat

    @State private var isHovering = false
    @State private var hoverLocation = CGPoint.zero

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                hoverFill
            }
            .overlay {
                hoverBorder
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovering = true
                    }
                case .ended:
                    withAnimation(.easeOut(duration: 0.20)) {
                        isHovering = false
                    }
                }
            }
    }

    private var hoverFill: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isHovering ? 0.22 : 0.0),
                            Color.accentColor.opacity(isHovering ? 0.10 : 0.0),
                            Color.clear
                        ],
                        center: hoverUnitPoint(in: proxy.size),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.42
                    )
                )
        }
        .allowsHitTesting(false)
    }

    private var hoverBorder: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [
                    Color.white.opacity(isHovering ? 0.92 : 0.0),
                    Color.accentColor.opacity(isHovering ? 0.32 : 0.0),
                    Color.clear
                ],
                center: hoverUnitPoint(in: proxy.size),
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.30
            )
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: 1.8)
            }
        }
        .allowsHitTesting(false)
    }

    private func hoverUnitPoint(in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else {
            return .center
        }

        let x = min(max(hoverLocation.x / size.width, 0), 1)
        let y = min(max(hoverLocation.y / size.height, 0), 1)
        return UnitPoint(x: x, y: y)
    }
}
