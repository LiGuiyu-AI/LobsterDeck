import SwiftUI

struct HeroCardView: View {
    let title: String
    let subtitle: String
    let accent: Color
    let accent2: Color
    let tags: [HeroTagItem]

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.88)
                if !tags.isEmpty {
                    tagRow.padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .bottomTrailing) { scribble }
        .frame(minHeight: 164)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: accent.opacity(0.35), radius: 22, y: 12)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(colors: [accent, accent2],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .opacity(0.94)
    }

    private var tagRow: some View {
        HStack(spacing: 8) {
            ForEach(tags.indices, id: \.self) { index in
                HeroTag(text: tags[index].text,
                        icon: tags[index].icon ?? "circle.fill")
            }
        }
    }

    private var scribble: some View {
        Image(systemName: "scribble.variable")
            .font(.system(size: 120, weight: .ultraLight))
            .foregroundStyle(.white.opacity(0.13))
            .offset(x: 16, y: 18)
            .allowsHitTesting(false)
    }
}
