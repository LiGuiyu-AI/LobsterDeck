import SwiftUI

struct AgentsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(state.agents) { a in
                        NavigationLink(value: Route.agent(a.agent)) {
                            AgentRow(agent: a)
                        }
                        .buttonStyle(.plain)
                    }
                    if state.agents.isEmpty {
                        GlassCard { EmptyHint(icon: "brain", text: "还没有读到 Agent 的记忆变化") }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await state.refreshAgents() }
            .navigationTitle("Agent")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .agent(let a): AgentDetailView(agent: a)
                case .commit(let sha): CommitDetailView(sha: sha)
                default: EmptyView()
                }
            }
        }
    }
}

struct AgentRow: View {
    let agent: AgentInfo
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 13) {
            AgentAvatar(name: agent.displayName, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.displayName).font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    Text("\(agent.commits30d ?? 0) 次 / 30天")
                    Text("·")
                    Text("\(agent.files ?? 0) 个记忆文件")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.relative(agent.last)).font(.caption2).foregroundStyle(.secondary)
                RowChevron()
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(Color.lobster.opacity(0.07)), in: .rect(cornerRadius: 20))
        .contentShape(Rectangle())
    }
}

// MARK: - Agent detail

struct AgentCommit: Codable, Identifiable, Equatable {
    var sha: String
    var author: String?
    var date: String?
    var subject: String
    var files: [String]
    var agent: String?

    var id: String { sha }
}

struct AgentCommits: Codable { var items: [AgentCommit] }

struct AgentDetailView: View {
    let agent: String
    @Environment(AppState.self) private var state

    @State private var commits: [AgentCommit] = []
    @State private var error: String?

    private var info: AgentInfo? { state.agents.first { $0.agent == agent } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                header
                ForEach(commits) { c in
                    NavigationLink(value: Route.commit(c.sha)) {
                        CommitRow(commit: c)
                    }
                    .buttonStyle(.plain)
                }
                if commits.isEmpty && error == nil {
                    GlassCard { EmptyHint(icon: "clock", text: "这位 Agent 最近没有记忆更新") }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(info?.displayName ?? agent)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 14) {
                AgentAvatar(name: info?.displayName ?? agent, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info?.displayName ?? agent).font(.headline)
                    Text("最近更新 \(Fmt.relative(info?.last))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(info?.commits30d ?? 0) 次提交 / 30 天")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private func load() async {
        do {
            let res: AgentCommits = try await state.client()
                .get("/api/v1/agents/\(agent)/commits", ["limit": "60"])
            commits = res.items
        } catch { self.error = error.localizedDescription }
    }
}

struct CommitRow: View {
    let commit: AgentCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.subject)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Text(commit.sha.prefix(7))
                    .font(.system(.caption2, design: .monospaced))
                Text("·")
                Text(Fmt.relative(commit.date))
                Spacer()
                if !commit.files.isEmpty {
                    Text("\(commit.files.count) 个文件")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.lobster.opacity(0.05)), in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}

// MARK: - Commit detail

struct CommitDetailView: View {
    let sha: String
    @Environment(AppState.self) private var state

    @State private var detail: CommitDetail?
    @State private var error: String?

    private var lines: [String] {
        guard let patch = detail?.patch else { return [] }
        return patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let d = detail {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.subject ?? "").font(.headline)
                            Text("\(d.author ?? "") · \(Fmt.day(d.date))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let body = d.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(body).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                            }
                        }
                    }

                    GlassCard(padding: 0) {
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(lines.prefix(600).enumerated()), id: \.offset) { _, line in
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(color(for: line))
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(12)
                        }
                    }
                    if lines.count > 600 {
                        Text("差异较长，仅显示前 600 行").font(.caption2).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("变更详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .secondary }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") { return .secondary }
        return .primary
    }

    private func load() async {
        do {
            detail = try await state.client().get("/api/v1/agents/commit", ["sha": sha])
        } catch { self.error = error.localizedDescription }
    }
}
