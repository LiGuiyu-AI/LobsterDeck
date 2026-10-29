import WebKit
import UIKit
import SwiftUI

struct ReportsView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""

    private var filtered: [Report] {
        guard !query.isEmpty else { return state.reports }
        return state.reports.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if filtered.isEmpty {
                        GlassCard { EmptyHint(icon: "doc.text.magnifyingglass", text: "没有找到报告") }
                            .padding(.top, 20)
                    } else {
                        GlassEffectContainer(spacing: 14) {
                            LazyVStack(spacing: 10) {
                                ForEach(filtered) { r in
                                    NavigationLink(value: Route.report(r.id)) {
                                        ReportRow(report: r)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await state.refreshReports() }
            .navigationTitle("报告")
            .searchable(text: $query, prompt: "搜索报告")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .report(let id): ReportDetailView(reportID: id)
                default: EmptyView()
                }
            }
        }
    }
}

struct ReportRow: View {
    let report: Report

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color.lobster.opacity(0.22), Color.lobster.opacity(0.08)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 42, height: 42)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.lobster)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(report.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(report.date ?? "")
                    if report.shared == true {
                        Label("共享中", systemImage: "lock.open.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            RowChevron()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.lobster.opacity(0.06)), in: .rect(cornerRadius: 20))
        .contentShape(Rectangle())
    }
}

// MARK: - Reader

struct ReportDetailView: View {
    let reportID: String
    @Environment(AppState.self) private var state

    @State private var html: String?
    @State private var error: String?
    @State private var showShare = false

    private var report: Report? { state.reports.first { $0.id == reportID } }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if let html {
                ReportWebView(html: html, baseURL: assetsURL)
                    .ignoresSafeArea(edges: .bottom)
            } else if let error {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.glass)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(report?.title ?? "报告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
            }
        }
        .sheet(isPresented: $showShare) {
            if let report {
                ReportTokenSheet(report: report)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
        .task { await load() }
    }

    private var assetsURL: URL? {
        guard let api = try? state.client() else { return nil }
        return api.base.appendingPathComponent("api/v1/report-assets/reports/")
    }

    private func load() async {
        error = nil
        do {
            let res: ReportHTML = try await state.client().get("/api/v1/reports/\(reportID)/html")
            html = res.html
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ReportWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            wv.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url,
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
