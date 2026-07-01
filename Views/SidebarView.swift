import SwiftUI

struct SidebarView: View {
    static let width: CGFloat = 236
    private static let horizontalPadding: CGFloat = 14

    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
                .frame(height: 12)

            ForEach(AppSection.allCases) { section in
                sidebarButton(for: section)
            }

            Spacer()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .frame(minWidth: Self.width, idealWidth: Self.width, maxWidth: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private func sidebarButton(for section: AppSection) -> some View {
        let isSelected = selection == section

        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 20)

                Text(section.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.18))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.42), lineWidth: 1)
                        }
                        .shadow(color: Color.accentColor.opacity(0.16), radius: 12, x: 0, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
    }
}
