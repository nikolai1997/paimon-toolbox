import SwiftUI
import WidgetKit

private struct WidgetSemanticForeground: ViewModifier {
    var fullColor: Color
    var fallbackOpacity: Double

    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                renderingMode == .fullColor
                    ? fullColor
                    : Color.white.opacity(fallbackOpacity)
            )
            .widgetAccentable(false)
    }
}

private struct WidgetStableForeground: ViewModifier {
    var fullColor: Color
    var fallbackOpacity: Double

    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                renderingMode == .fullColor
                    ? fullColor
                    : Color.white.opacity(fallbackOpacity)
            )
            .widgetAccentable(false)
    }
}

private struct WidgetReadableForeground: ViewModifier {
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.white.opacity(opacity))
            .widgetAccentable(false)
    }
}

private struct WidgetFullColorTintBackground: ViewModifier {
    var tint: Color
    var cornerRadius: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(renderingMode == .fullColor ? tint.opacity(0.24) : Color.black.opacity(0.12))
            }
    }
}

extension View {
    fileprivate func widgetStablePrimary() -> some View {
        modifier(WidgetStableForeground(fullColor: .primary, fallbackOpacity: 0.96))
    }

    fileprivate func widgetStableSecondary() -> some View {
        modifier(WidgetStableForeground(fullColor: .secondary, fallbackOpacity: 0.82))
    }

    fileprivate func widgetReadablePrimary() -> some View {
        modifier(WidgetReadableForeground(opacity: 0.96))
    }

    fileprivate func widgetReadableSecondary() -> some View {
        modifier(WidgetReadableForeground(opacity: 0.78))
    }

    fileprivate func widgetNativePrimary() -> some View {
        foregroundStyle(.primary)
    }

    fileprivate func widgetNativeSecondary() -> some View {
        foregroundStyle(.secondary)
    }

    fileprivate func widgetSemanticForeground(_ fullColor: Color, fallbackOpacity: Double = 0.92) -> some View {
        modifier(WidgetSemanticForeground(fullColor: fullColor, fallbackOpacity: fallbackOpacity))
    }

    fileprivate func widgetTintBackground(_ tint: Color, cornerRadius: CGFloat) -> some View {
        modifier(WidgetFullColorTintBackground(tint: tint, cornerRadius: cornerRadius))
    }
}

extension Image {
    @ViewBuilder
    fileprivate func widgetAccentedSymbol() -> some View {
        if #available(macOS 15.0, *) {
            widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}

struct SmallSignInWidgetView: View {
    var snapshot: WidgetSnapshot
    var isInteractive = true

    private var signIn: WidgetSignInSnapshot {
        snapshot.signIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: signIn.isTodaySigned ? "checkmark.seal.fill" : "seal")
                    .widgetAccentedSymbol()
                    .font(.system(size: 28, weight: .semibold))
                    .widgetSemanticForeground(signIn.isTodaySigned ? .green : .orange)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .widgetAccentedSymbol()
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .widgetNativeSecondary()

                    Text(signIn.isTodaySigned ? "已签到" : "待签到")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .widgetNativeSecondary()
                }
                .accessibilityLabel("刷新")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(signIn.nickname ?? "旅行者")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetNativePrimary()

                Text(signIn.uid.map { "UID \($0)" } ?? signIn.message ?? "登录后显示签到状态")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .widgetNativeSecondary()
            }

            Text(signIn.isTodaySigned ? "刷新状态" : "去签到")
                .font(.system(size: 11, weight: .regular, design: .default))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetNativePrimary()
        }
        .padding(16)
        .frame(width: 158, height: 158, alignment: .leading)
    }
}

struct MediumGachaWidgetView: View {
    var snapshot: WidgetSnapshot
    var isInteractive = true

    private var gacha: WidgetGachaSnapshot {
        snapshot.gacha
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .widgetAccentedSymbol()
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .widgetNativePrimary()

                        Text("祈愿记录")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .widgetNativePrimary()
                    }

                    Text(gacha.lastFiveStarName)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .widgetNativePrimary()

                    Text(gacha.totalPulls == 0 ? "同步记录后显示五星与垫数" : "最近五星")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .lineLimit(1)
                        .widgetNativeSecondary()
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .widgetAccentedSymbol()
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .widgetNativeSecondary()

                    Text("刷新")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .widgetNativeSecondary()
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                CompactWidgetMetric(title: "总抽数", value: "\(gacha.totalPulls)", systemImage: "tray.full", tint: .blue)
                CompactWidgetMetric(title: "当前垫数", value: "\(gacha.pitySinceLastFiveStar)", systemImage: "clock.arrow.circlepath", tint: .orange)
                CompactWidgetMetric(title: "五星", value: "\(gacha.fiveStarCount)", systemImage: "star", tint: .purple)
            }
        }
        .padding(16)
        .frame(width: 338, height: 158, alignment: .leading)
    }
}

struct LargeToolboxWidgetView: View {
    var snapshot: WidgetSnapshot
    var isInteractive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                LargeWidgetSummaryCard(
                    title: "待签到",
                    value: snapshot.signIn.statusText,
                    detail: signInDetail,
                    systemImage: snapshot.signIn.isTodaySigned ? "checkmark.seal.fill" : "seal",
                    tint: snapshot.signIn.isTodaySigned ? .green : .orange
                )

                LargeWidgetSummaryCard(
                    title: "祈愿记录",
                    value: "\(snapshot.gacha.totalPulls) 抽",
                    detail: "垫数 \(snapshot.gacha.pitySinceLastFiveStar) · 五星 \(snapshot.gacha.fiveStarCount)",
                    systemImage: "sparkles",
                    tint: .purple
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .widgetAccentedSymbol()
                        .font(.headline.weight(.medium))
                        .widgetReadablePrimary()

                    Text("今日养成")
                        .font(.headline.weight(.regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .widgetReadablePrimary()
                }

                if snapshot.planner.rows.isEmpty {
                    Text("暂无待完成养成材料")
                        .font(.subheadline)
                        .lineLimit(1)
                        .widgetReadableSecondary()
                } else {
                    ForEach(snapshot.planner.rows.prefix(2)) { row in
                        PlannerWidgetRow(row: row)
                    }
                }
            }
            .padding(12)
            .widgetTintBackground(.blue, cornerRadius: 18)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .widgetAccentedSymbol()
                        .font(.headline.weight(.medium))
                        .widgetReadablePrimary()

                    Text("打开工具箱")
                        .font(.headline.weight(.regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .widgetReadablePrimary()
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .widgetAccentedSymbol()
                        .font(.headline.weight(.medium))
                        .widgetReadablePrimary()

                    Text("刷新")
                        .font(.headline.weight(.regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .widgetReadablePrimary()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .widgetTintBackground(.blue, cornerRadius: 18)
        }
        .padding(18)
        .frame(width: 338, height: 354, alignment: .topLeading)
    }

    private var signInDetail: String {
        if snapshot.signIn.isTodaySigned {
            return "本月 \(snapshot.signIn.totalSignDay) 天"
        }
        return snapshot.signIn.actionTitle == "去签到" ? "去签到" : snapshot.signIn.actionTitle
    }
}

private struct CompactWidgetMetric: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .widgetAccentedSymbol()
                    .font(.caption2.weight(.medium))
                    .widgetNativePrimary()

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .widgetNativePrimary()
            }

            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetNativePrimary()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetTintBackground(tint, cornerRadius: 16)
    }
}

private struct LargeWidgetSummaryCard: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .widgetAccentedSymbol()
                .font(.system(size: 24, weight: .semibold))
                .widgetReadablePrimary()

            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .widgetReadableSecondary()

            Text(value)
                .font(.title3.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .widgetReadablePrimary()

            Text(detail)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .widgetReadableSecondary()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetTintBackground(tint, cornerRadius: 18)
    }
}

private struct PlannerWidgetRow: View {
    var row: WidgetPlannerRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.targetName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .widgetStablePrimary()

                Spacer(minLength: 0)

                Text("\(row.owned)/\(row.required)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .widgetStableSecondary()
            }

            ProgressView(value: min(max(row.completion, 0), 1))
                .controlSize(.mini)
                .tint(.accentColor)

            Text(row.materialName)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetStableSecondary()
        }
    }
}

struct SmallWidgetSystemPlaceholderView: View {
    var body: some View {
        SmallSignInWidgetView(snapshot: .empty, isInteractive: false)
    }
}

struct MediumWidgetSystemPlaceholderView: View {
    var body: some View {
        MediumGachaWidgetView(snapshot: .empty, isInteractive: false)
    }
}

struct LargeWidgetSystemPlaceholderView: View {
    var body: some View {
        LargeToolboxWidgetView(snapshot: .empty, isInteractive: false)
    }
}

#if DEBUG && !WIDGET_EXTENSION_BUNDLE_BUILD
#Preview("Small Widget") {
    SmallSignInWidgetView(snapshot: .empty)
}

#Preview("Medium Widget") {
    MediumGachaWidgetView(snapshot: .empty)
}

#Preview("Large Widget") {
    LargeToolboxWidgetView(snapshot: .empty)
}
#endif
