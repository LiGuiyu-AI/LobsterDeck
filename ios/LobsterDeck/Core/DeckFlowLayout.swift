import SwiftUI

/// A LayoutValue key so each card can declare how many columns it wants.
struct DeckSpanKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

extension View {
    func deckSpan(_ value: Int) -> some View {
        layoutValue(key: DeckSpanKey.self, value: value)
    }
}

/// Ragged masonry: full-width cards break the row, half cards fall into the
/// shorter column, so panels pack together instead of forming aligned gaps.
struct DeckFlowLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0 else { return .zero }
        let cw = columnWidth(total: width)
        var heights = Array(repeating: CGFloat.zero, count: columns)

        for sub in subviews {
            let span = max(1, min(columns, sub[DeckSpanKey.self]))
            let w = span == columns ? width : cw
            let size = sub.sizeThatFits(ProposedViewSize(width: w, height: nil))
            if span == columns {
                let y = heights.max() ?? 0
                for i in heights.indices { heights[i] = y + size.height + spacing }
            } else {
                let col = shortest(heights)
                heights[col] += size.height + spacing
            }
        }
        return CGSize(width: width, height: max(0, (heights.max() ?? spacing) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let cw = columnWidth(total: bounds.width)
        var heights = Array(repeating: CGFloat.zero, count: columns)

        for sub in subviews {
            let span = max(1, min(columns, sub[DeckSpanKey.self]))
            let w = span == columns ? bounds.width : cw
            let size = sub.sizeThatFits(ProposedViewSize(width: w, height: nil))

            if span == columns {
                let y = heights.max() ?? 0
                sub.place(at: CGPoint(x: bounds.minX, y: bounds.minY + y),
                          proposal: ProposedViewSize(width: w, height: size.height))
                for i in heights.indices { heights[i] = y + size.height + spacing }
            } else {
                let col = shortest(heights)
                let x = bounds.minX + CGFloat(col) * (cw + spacing)
                let y = heights[col]
                sub.place(at: CGPoint(x: x, y: bounds.minY + y),
                          proposal: ProposedViewSize(width: w, height: size.height))
                heights[col] = y + size.height + spacing
            }
        }
    }

    private func columnWidth(total: CGFloat) -> CGFloat {
        max(0, (total - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func shortest(_ heights: [CGFloat]) -> Int {
        heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
    }
}

struct HeroTag: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.18), in: .capsule)
    }
}
