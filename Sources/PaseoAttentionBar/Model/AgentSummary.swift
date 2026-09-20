import Foundation

/// デーモンの `deriveAgentStateBucket` と同じ分類。
/// 優先度順（数値が小さいほど先に見せる）。
enum AgentBucket: Int, Comparable {
    case needsInput = 0   // 権限確認・質問待ち（permission）
    case failed = 1       // エラー終了
    case running = 2      // 実行中
    case attention = 3    // 完了・ユーザー確認待ち（finished）
    case done = 4         // 確認済み

    static func < (lhs: AgentBucket, rhs: AgentBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    /// ユーザーの操作を待っているもの（メニューバーに出す対象）
    var needsUser: Bool {
        switch self {
        case .needsInput, .failed, .attention: return true
        case .running, .done: return false
        }
    }
}

/// `fetch_agents_response` / `agent_update` の agent スナップショットから
/// メニューバー表示に必要な項目だけ抜いたもの。
struct AgentSummary: Identifiable, Equatable {
    let id: String
    var title: String
    var status: String
    var cwd: String
    var provider: String
    var model: String?
    var projectName: String?
    var workspaceName: String?
    var requiresAttention: Bool
    var attentionReason: String?
    var attentionTimestamp: Date?
    var pendingPermissionCount: Int
    var pendingPermissionTitle: String?
    var lastError: String?
    var updatedAt: Date?
    var archived: Bool

    var bucket: AgentBucket {
        if pendingPermissionCount > 0 || attentionReason == "permission" { return .needsInput }
        if status == "error" || attentionReason == "error" { return .failed }
        if status == "running" { return .running }
        if requiresAttention { return .attention }
        return .done
    }

    /// 並べ替え・経過時間表示に使う「注意が必要になった時刻」
    var attentionDate: Date { attentionTimestamp ?? updatedAt ?? .distantPast }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "（無題）" : t
    }

    var displayProject: String {
        if let p = projectName, !p.isEmpty {
            if let w = workspaceName, !w.isEmpty, w != "Main" { return "\(p) · \(w)" }
            return p
        }
        return (cwd as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - JSON からの復元

    // ISO8601DateFormatter はスレッド安全（Apple ドキュメント）なので共有してよい
    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return isoWithFraction.date(from: s) ?? isoPlain.date(from: s)
    }

    /// `agent` オブジェクトと（あれば）`project` オブジェクトから組み立てる。
    init?(agent: [String: Any], project: [String: Any]?) {
        guard let id = agent["id"] as? String else { return nil }
        self.id = id
        self.title = (agent["title"] as? String) ?? ""
        self.status = (agent["status"] as? String) ?? "unknown"
        self.cwd = (agent["cwd"] as? String) ?? ""
        self.provider = (agent["provider"] as? String) ?? ""
        self.model = agent["model"] as? String
        self.projectName = project?["projectName"] as? String
        self.workspaceName = project?["workspaceName"] as? String
        self.requiresAttention = (agent["requiresAttention"] as? Bool) ?? false
        self.attentionReason = agent["attentionReason"] as? String
        self.attentionTimestamp = AgentSummary.parseDate(agent["attentionTimestamp"])
        let permissions = (agent["pendingPermissions"] as? [[String: Any]]) ?? []
        self.pendingPermissionCount = permissions.count
        self.pendingPermissionTitle = permissions.first.flatMap {
            ($0["title"] as? String) ?? ($0["name"] as? String)
        }
        self.lastError = agent["lastError"] as? String
        self.updatedAt = AgentSummary.parseDate(agent["updatedAt"])
        self.archived = (agent["archivedAt"] as? String) != nil
    }
}
