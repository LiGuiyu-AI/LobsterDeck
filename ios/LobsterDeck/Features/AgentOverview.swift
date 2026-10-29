import SwiftUI

struct AgentOverviewCard: View {
    let repo: RepoStats
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                tile("COMMITS", "\(repo.commits ?? 0)")
                tile("FILES", "\(repo.files ?? 0)")
                tile("REPO", repo.size ?? "-")
                tile("BRANCH", repo.branch ?? "-")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("数据源 Forgejo", color: .green)
                    chip("记忆文件 \(repo.memoryDirsWithMd ?? 0)/\(repo.memoryDirs ?? 0)", color: .yellow)
                    chip("最后提交 \(Fmt.relative(repo.lastCommit))", color: .orange)
                    chip("Markdown \(repo.markdownFiles ?? 0)", color: .blue)
                }
            }
            .scrollIndicators(.hidden)

            if !compact, let daily = repo.daily, !daily.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("近 30 天提交").font(.caption.weight(.semibold))
                        Spacer()
                        Text(String(totalCommits(daily))).font(.caption2).foregroundStyle(.secondary)
                    }
                    ActivityChart(daily: daily)
                        .frame(height: 92)
                    axisLabels(daily)
                }
            }
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }

    private func chip(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.primary.opacity(0.05), in: .capsule)
        .overlay(Capsule().strokeBorder(.gray.opacity(0.2), lineWidth: 0.8))
    }

    private func axisLabels(_ daily: [DailyPoint]) -> some View {
        HStack {
            Text(short(daily.first?.date))
            Spacer()
            Text(short(daily[daily.count / 2].date))
            Spacer()
            Text(short(daily.last?.date))
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }

    private func totalCommits(_ daily: [DailyPoint]) -> Int {
        daily.reduce(0) { $0 + $1.total }
    }

    private func short(_ d: String?) -> String {
        guard let d, d.count >= 10 else { return "" }
        return String(d.dropFirst(5).prefix(5))
    }
}

struct ActivityChart: View {
    let daily: [DailyPoint]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(1, daily.map(\.total).max() ?? 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(daily) { day in
                    VStack(spacing: 0) {
                        ForEach(day.agents, id: \.agent) { slice in
                            Rectangle()
                                .fill(Color(hexString: slice.color) ?? .lobster)
                                .frame(height: max(1, CGFloat(slice.count) / CGFloat(maxV) * (geo.size.height - 2)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}
