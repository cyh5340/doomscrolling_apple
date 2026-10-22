import DoomscrollKit
import SwiftUI

/// Content is capped so iPads get a readable column instead of edge-to-edge text.
let maxContentWidth: CGFloat = 640

/// Standard screen: large title, scrolling content column on the brand background.
struct Screen<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 88) // room for the floating button
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Brand.background, for: .navigationBar)
    }
}

extension View {
    /// Rounded container card.
    func card(_ color: Color = Brand.surfaceContainer, radius: CGFloat = 28, padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Brand.onSurfaceVariant)
            .padding(.top, 8)
    }
}

/// Warning card with an optional action.
struct Notice<Extra: View>: View {
    let text: String
    var action: String?
    var onAction: () -> Void = {}
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.subheadline)
            extra
            if let action {
                Button(action, action: onAction)
                    .buttonStyle(.bordered)
                    .tint(Brand.onErrorContainer)
            }
        }
        .foregroundStyle(Brand.onErrorContainer)
        .card(Brand.errorContainer, radius: 16, padding: 16)
    }
}

extension Notice where Extra == EmptyView {
    init(_ text: String, action: String? = nil, onAction: @escaping () -> Void = {}) {
        self.init(text: text, action: action, onAction: onAction) { EmptyView() }
    }
}

private let avatarColors: [UInt32] = [0xFF7A45, 0x8C7CFF, 0x4ADE9B, 0xF5B83D, 0x4CB8F5, 0xF06292, 0x26C6DA]

/// Initial on a color picked from the name, so each friend keeps the same color.
struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        // A stable hash: String.hashValue changes between launches.
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        Circle()
            .fill(Color(rgb: avatarColors[hash % avatarColors.count]))
            .frame(width: size, height: size)
            .overlay {
                Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased().ifEmpty("?"))
                    .font(size >= 40 ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(Brand.ink)
            }
    }
}

struct Pill: View {
    let text: String
    var container: Color = Brand.surfaceContainerHighest
    var content: Color = Brand.onSurface

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(content)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(container, in: Capsule())
    }
}

/// Emoji in a tinted circle: used for onboarding steps and info rows.
struct EmojiBadge: View {
    let emoji: String
    var size: CGFloat = 44
    var container: Color = Brand.primaryContainer

    var body: some View {
        Circle().fill(container).frame(width: size, height: size)
            .overlay { Text(emoji).font(.system(size: size * 0.45)) }
    }
}

struct InfoRow: View {
    let emoji: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            EmojiBadge(emoji: emoji, container: Brand.surfaceContainerHigh)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(Brand.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Full-width primary button.
struct BigButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(filled ? Brand.onPrimary : Brand.primary)
            .background {
                if filled {
                    Capsule().fill(Brand.primary)
                } else {
                    Capsule().strokeBorder(Brand.outlineVariant, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Wrapping row of pills or chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

extension StringProtocol {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : String(self) }
}

/// Group rules as short, emoji-led phrases.
func rules(daily: Int, session: Int?, streak: Int) -> [String] {
    var out = ["⏱ \(formatMinutes(daily)) a day"]
    if let session { out.append("⚡ \(formatMinutes(session)) in one go") }
    out.append("🔥 streak at \(streak) days")
    return out
}
