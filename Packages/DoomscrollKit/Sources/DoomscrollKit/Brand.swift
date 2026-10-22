#if os(iOS)
import SwiftUI
import UIKit

/// Ember (limits, "doom") on ink, with mint for "under the limit". Same palette as the Android app.
public enum Brand {
    public static let primary = dynamic(0xD9480F, 0xFF7A45)
    public static let onPrimary = dynamic(0xFFFFFF, 0x2A0E00)
    public static let primaryContainer = dynamic(0xFFE1D3, 0x4A1E0A)
    public static let onPrimaryContainer = dynamic(0x3A1100, 0xFFDBCB)
    public static let secondary = dynamic(0x5B4DD6, 0xB4A7FF)
    public static let onSecondary = dynamic(0xFFFFFF, 0x1E1557)
    public static let secondaryContainer = dynamic(0xE6E1FF, 0x2E2766)
    public static let tertiary = dynamic(0x0E8F5B, 0x4ADE9B)
    public static let tertiaryContainer = dynamic(0xCFF5E1, 0x0F3D2A)
    public static let onTertiaryContainer = dynamic(0x00301A, 0xB6F5D3)
    public static let error = dynamic(0xC8243A, 0xFF6B7A)
    public static let errorContainer = dynamic(0xFFDADC, 0x4A1219)
    public static let onErrorContainer = dynamic(0x410009, 0xFFDADC)
    public static let background = dynamic(0xFAF8F6, 0x0D0E12)
    public static let onSurface = dynamic(0x16171B, 0xECEDF2)
    public static let onSurfaceVariant = dynamic(0x5E616B, 0x9BA1B0)
    public static let surfaceContainer = dynamic(0xF0ECE8, 0x181A20)
    public static let surfaceContainerHigh = dynamic(0xEAE6E2, 0x1F2229)
    public static let surfaceContainerHighest = dynamic(0xE4DFDA, 0x272A33)
    public static let outlineVariant = dynamic(0xDEDAD5, 0x2A2D36)
    /// Dark text on bright avatar and medal colors, in both themes.
    public static let ink = Color(rgb: 0x14151A)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    public init(rgb: UInt32) { self.init(uiColor: UIColor(rgb: rgb)) }
}

/// Ring of today's minutes against the strictest group's daily limit. Used by the report extension (exact
/// minutes) and by the app as a fallback (15-minute buckets).
public struct TodayRing: View {
    let minutes: Int
    let limit: Int?
    let exact: Bool

    nonisolated public init(minutes: Int, limit: Int?, exact: Bool) {
        self.minutes = minutes
        self.limit = limit
        self.exact = exact
    }

    public var body: some View {
        let progress = limit.map { min(Double(minutes) / Double($0), 1) } ?? 0
        let ringColor: Color = switch limit {
        case nil: Brand.secondary
        case let l? where minutes >= l: Brand.error
        case _ where progress >= 0.75: Brand.primary
        default: Brand.tertiary
        }
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(Brand.surfaceContainerHighest, lineWidth: 14)
                Circle().trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(formatMinutes(minutes)).font(.system(size: 44, weight: .bold)).monospacedDigit()
                    Text("in social apps").font(.subheadline).foregroundStyle(Brand.onSurfaceVariant)
                }
            }
            .frame(width: 212, height: 212)
            Group {
                if let limit {
                    Text(minutes >= limit
                         ? "Over your group's \(formatMinutes(limit)) limit. They've been told."
                         : "\(formatMinutes(limit - minutes)) left before your group hears about it.")
                } else {
                    Text("Join a group to get a daily limit.")
                }
            }
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            Text(exact
                 ? "Friends see \(formatMinutes(minutes / 15 * 15)): time is shared in 15-minute steps."
                 : "Time is shared with friends in 15-minute steps.")
                .font(.caption)
                .foregroundStyle(Brand.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Brand.onSurface)
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
#endif
