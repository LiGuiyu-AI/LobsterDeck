import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var showSettings = false

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    header

                    if let s = state.overview?.stats {
                        statRow(s)
                    }

                    if let modules = state.overview?.modules {
                        GlassEffectContainer(spacing: 18) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                                GridItem(.flexible(), spacing: 14)],
                                      spacing: 14) {
                                ForEach(modules) { m in
                                    moduleView(m)
                                        .gridCellColumns(span(m))
                                        .transition(.opacity)
                                }
                            }
                        }
                    } else if state.isLoading {
                        skeleton
                    } else if let err = state.lastError {
                        GlassCard {
                            VStack(spacing: 10) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.system(size: 24)).foregroundStyle(.secondary)
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("重新加载") { Task { await state.refreshAll() } }
                                    .buttonStyle(.glass)
                            }
                        }
                    } else {
                        GlassCard {
                            VStack(spacing: 10) {
                                EmptyHint(icon: "sparkles", text: "还没有内容")
                                Button("加载") { Task { await state.refreshAll() } }
                                    .buttonStyle(.glass)
                            }
                        }
                    }

                    footer
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable { await state.refreshAll() }
            .task {
                if state.overview == nil { await state.refreshAll() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("LOBSTER DECK")
                        .font(.caption2.weight(.black))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("设置")
                }
            }
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .overlay(alignment: .bottom) {
                if let err = state.lastError {
                    Text(err)
                        .font(.caption)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassEffect(.regular.tint(.red.opacity(0.35)), in: .capsule)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.greeting())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    private func statRow(_ s: Overview.Stats) -> some View {
        HStack(spacing: 10) {
            stat("报告", value: s.reports ?? 0, icon: "doc.text")
            stat("Agent", value: s.agents ?? 0, icon: "brain.head.profile")
            stat("新文件", value: s.files ?? 0, icon: "tray.full")
        }
    }

    private func stat(_ label: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2.weight(.bold))
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassEffect(.regular.tint(.lobster.opacity(0.10)), in: .rect(cornerRadius: 20))
    }

    // MARK: modules

    private func span(_ m: Module) -> Int {
        switch (m.size ?? "large") {
        case "small": return 1
        default: return 2
        }
    }

    @ViewBuilder
    private func moduleView(_ m: Module) -> some View {
        switch m.kind ?? "list" {
        case "hero": heroCard(m)
        case "agents": agentCard(m)
        case "actions": actionCard(m)
        default: listCard(m)
        }
    }

    private func heroCard(_ m: Module) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color.lobster, Color.lobsterDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.92)

            Image(systemName: "scribble.variable")
                .font(.system(size: 130, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.14))
                .offset(x: 18, y: 22)

            VStack(alignment: .leading, spacing: 8) {
                Text(m.title ?? "你好")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(m.subtitle ?? "")
                    .font(.subheadline)
                    .opacity(0.86)
                HStack(spacing: 8) {
                    GlassPill(text: "已同步", icon: "checkmark.circle.fill", tint: .white)
                    if let t = state.lastRefresh {
                        GlassPill(text: Fmt.relative(Fmt.iso.string(from: t)), icon: "clock", tint: .white)
                    }
                }
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minHeight: 172)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .lobster.opacity(0.35), radius: 22, y: 12)
    }

    private func listCard(_ m: Module) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: m.title ?? "", subtitle: m.subtitle)
                let items = m.items ?? []
                if items.isEmpty {
                    EmptyHint(icon: "tray", text: "暂时没有新内容")
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            rowLink(item, source: m.source)
                            if idx < items.count - 1 {
                                Divider().opacity(0.35).padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowLink(_ item: Item, source: String?) -> some View {
        switch source {
        case "reports":
            if let id = item.id {
                NavigationLink(value: Route.report(id)) { DeckRow(item: item, icon: "doc.text.fill", tint: .lobster) }
                    .buttonStyle(.plain)
            } else { DeckRow(item: item, icon: "doc.text.fill", tint: .lobster) }
        case "files":
            if let path = item.path {
                NavigationLink(value: Route.file(path)) { DeckRow(item: item, icon: "doc.fill", tint: .orange) }
                    .buttonStyle(.plain)
            } else { DeckRow(item: item, icon: "doc.fill", tint: .orange) }
        default:
            DeckRow(item: item, icon: "circle.fill", tint: .lobster)
        }
    }

    private func agentCard(_ m: Module) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: m.title ?? "Agent", subtitle: m.subtitle)
                ForEach(m.items ?? [], id: \.stableID) { item in
                    if let name = item.agent {
                        NavigationLink(value: Route.agent(name)) {
                            HStack(spacing: 12) {
                                AgentAvatar(name: item.title, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    Text(item.detail ?? item.subtitle ?? "")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                RowChevron()
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func actionCard(_ m: Module) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: m.title ?? "快捷入口")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(m.items ?? [], id: \.stableID) { item in
                        Button {
                            if let s = item.url, let u = URL(string: s) { openURL(u) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: item.icon ?? "link")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.lobster)
                                Text(item.title).font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let s = item.subtitle {
                                    Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var skeleton: some View {
        GlassCard { EmptyHint(icon: "hourglass", text: "正在读取你的空间…") }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("由 🦞 与各 Agent 共同编排")
            if let t = state.overview?.layoutUpdatedAt {
                Text("布局更新于 \(Fmt.relative(t))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .report(let id): ReportDetailView(reportID: id)
        case .folder(let path): FileBrowserView(path: path)
        case .file(let path): FilePreviewScreen(path: path)
        case .agent(let name): AgentDetailView(agent: name)
        case .commit(let sha): CommitDetailView(sha: sha)
        }
    }
}

// MARK: - Shared row

struct DeckRow: View {
    let item: Item
    var icon: String = "circle.fill"
    var tint: Color = .lobster

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if item.new == true {
                        Text("NEW")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.lobster, in: .capsule)
                            .foregroundStyle(.white)
                    }
                    if item.shared == true {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                if let s = item.subtitle {
                    Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            RowChevron()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct AgentAvatar: View {
    let name: String
    var size: CGFloat = 40

    private var hue: Double {
        Double(abs(name.hashValue % 360)) / 360.0
    }

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                        Color(hue: hue, saturation: 0.75, brightness: 0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Text(String(name.prefix(2)))
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
