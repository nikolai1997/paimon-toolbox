import SwiftUI

struct SidebarView: View {
    static let width: CGFloat = 236
    private static let horizontalPadding: CGFloat = 14

    @Binding var selection: AppSection
    @AppStorage(SidebarVisibility.key) private var hiddenSections = ""
    @State private var isPresentingDonation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
                .frame(height: 12)

            ForEach(AppSection.allCases.filter { SidebarVisibility.isVisible($0, hidden: hiddenSections) }) { section in
                sidebarButton(for: section)
            }

            Spacer()

            Button {
                isPresentingDonation = true
            } label: {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("支持开发者")
            .accessibilityIdentifier("donation-support-button")
            .delayedTooltip("请开发者喝杯咖啡")
            .padding(.leading, 12)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .frame(minWidth: Self.width, idealWidth: Self.width, maxWidth: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $isPresentingDonation) {
            DonationSupportView()
        }
        .onAppear {
            if !SidebarVisibility.isVisible(selection, hidden: hiddenSections) {
                selection = .settings
            }
        }
        .onChange(of: hiddenSections) { _, value in
            if !SidebarVisibility.isVisible(selection, hidden: value) {
                selection = .settings
            }
        }
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
