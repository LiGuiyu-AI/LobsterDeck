import Foundation

struct Overview: Codable, Equatable {
    var generatedAt: String?
    var layoutUpdatedAt: String?
    var generatedBy: String?
    var stats: Stats?
    var modules: [Module]

    struct Stats: Codable, Equatable {
        var reports: Int?
        var files: Int?
        var agents: Int?
    }
}

struct Module: Codable, Identifiable, Equatable {
    var id: String
    var kind: String?
    var size: String?
    var title: String?
    var subtitle: String?
    var accent: String?
    var source: String?
    var limit: Int?
    var items: [Item]?
}

struct Item: Codable, Equatable {
    var title: String
    var subtitle: String?
    var detail: String?
    var id: String?
    var path: String?
    var agent: String?
    var url: String?
    var icon: String?
    var new: Bool?
    var shared: Bool?

    var stableID: String { id ?? path ?? url ?? title }
    var identity: String { stableID }
}

struct Report: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var date: String?
    var modified: String?
    var size: Int?
    var shared: Bool?
}

struct ReportList: Codable { var items: [Report] }
struct ReportHTML: Codable { var id: String; var html: String }
struct TokenList: Codable { var tokens: [String: String] }

struct FileEntry: Codable, Identifiable, Equatable {
    var name: String
    var path: String
    var isDir: Bool?
    var size: Int?
    var sizeH: String?
    var mtime: String?
    var new: Bool?
    var changed: Bool?

    var id: String { path }
    var isDirectory: Bool { isDir ?? false }
}

struct FileListing: Codable {
    var path: String
    var dirs: [FileEntry]
    var files: [FileEntry]
}

struct RecentFiles: Codable { var items: [FileEntry] }

struct AgentInfo: Codable, Identifiable, Equatable {
    var agent: String
    var label: String?
    var commits: Int?
    var commits30d: Int?
    var files: Int?
    var last: String?
    var recent: [RecentCommit]?

    var id: String { agent }
    var displayName: String { label ?? agent }
    var initials: String { String(displayName.prefix(2)) }
}

struct RecentCommit: Codable, Equatable {
    var sha: String
    var subject: String
    var date: String?
}

struct AgentList: Codable { var items: [AgentInfo] }

struct CommitDetail: Codable {
    var sha: String
    var author: String?
    var email: String?
    var date: String?
    var subject: String?
    var body: String?
    var patch: String?
}

struct Health: Codable {
    var ok: Bool
    var version: String?
    var time: String?
}
