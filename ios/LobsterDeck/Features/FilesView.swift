import SwiftUI
import QuickLook
import UIKit

struct FilesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !state.recentFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "最近变化", subtitle: "文件站里最新落下的东西")
                            GlassEffectContainer(spacing: 12) {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 12) {
                                        ForEach(state.recentFiles) { f in
                                            NavigationLink(value: Route.file(f.path)) {
                                                RecentFileCard(file: f)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }
                    }

                    FileBrowserView(path: "")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await state.refreshAll() }
            .navigationTitle("文件")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let p): FileBrowserView(path: p)
                case .file(let p): FilePreviewScreen(path: p)
                default: EmptyView()
                }
            }
        }
    }
}

struct RecentFileCard: View {
    let file: FileEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon(file.name))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.lobster)
                Spacer()
                if file.new == true {
                    Text("NEW")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.lobster, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            Text(file.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(file.sizeH ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 168, height: 118, alignment: .topLeading)
        .glassEffect(.regular.tint(Color.lobster.opacity(0.10)), in: .rect(cornerRadius: 20))
        .contentShape(Rectangle())
    }

    private func icon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "png", "jpg", "jpeg", "heic", "webp": return "photo"
        case "zip", "7z", "rar": return "archivebox"
        case "md", "txt": return "text.alignleft"
        default: return "doc"
        }
    }
}

struct FileBrowserView: View {
    let path: String
    @Environment(AppState.self) private var state

    @State private var listing: FileListing?
    @State private var error: String?

    var body: some View {
        Group {
            if let listing {
                VStack(alignment: .leading, spacing: 12) {
                    if !listing.dirs.isEmpty {
                        SoftList {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(listing.dirs.enumerated()), id: \.element.id) { idx, d in
                                    NavigationLink(value: Route.folder(d.path)) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 15))
                                                .foregroundStyle(Color.lobster)
                                                .frame(width: 30)
                                            Text(d.name).font(.subheadline)
                                            Spacer()
                                            RowChevron()
                                        }
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if idx < listing.dirs.count - 1 { Divider().opacity(0.3).padding(.leading, 42) }
                                }
                            }
                        }
                    }

                    if !listing.files.isEmpty {
                        SoftList {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(listing.files.enumerated()), id: \.element.id) { idx, f in
                                    NavigationLink(value: Route.file(f.path)) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "doc.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 30)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(f.name).font(.subheadline).lineLimit(1)
                                                Text("\(f.sizeH ?? "") · \(Fmt.day(f.mtime))")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            RowChevron()
                                        }
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if idx < listing.files.count - 1 { Divider().opacity(0.3).padding(.leading, 42) }
                                }
                            }
                        }
                    }

                    if listing.dirs.isEmpty && listing.files.isEmpty {
                        GlassCard { EmptyHint(icon: "folder", text: "这里是空的") }
                    }
                }
            } else if let error {
                GlassCard {
                    VStack(spacing: 10) {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("重试") { Task { await load() } }.buttonStyle(.glass)
                    }
                }
            } else {
                GlassCard { EmptyHint(icon: "hourglass", text: "读取中…") }
            }
        }
        .navigationTitle(path.isEmpty ? "文件站" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let res: FileListing = try await state.client().get("/api/v1/files", ["path": path])
            listing = res
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - File preview

struct FilePreviewScreen: View {
    let path: String
    @Environment(AppState.self) private var state

    @State private var localURL: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let localURL {
                QuickLookView(url: localURL)
                    .ignoresSafeArea(edges: .bottom)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("正在取回文件…")
            }
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { await download() }
    }

    private func download() async {
        do {
            let data = try await state.client().rawFile(path: path)
            let name = (path as NSString).lastPathComponent
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            localURL = url
        } catch { self.error = error.localizedDescription }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ c: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
