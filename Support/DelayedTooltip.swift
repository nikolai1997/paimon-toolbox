import SwiftUI

struct DelayedTooltipModifier: ViewModifier {
    let text: String
    var delayNanoseconds: UInt64 = 1_000_000_000

    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                hoverTask?.cancel()

                if isHovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: delayNanoseconds)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            isPresented = true
                        }
                    }
                } else {
                    isPresented = false
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 280, alignment: .leading)
            }
    }
}

extension View {
    func delayedTooltip(_ text: String) -> some View {
        modifier(DelayedTooltipModifier(text: text))
    }
}
