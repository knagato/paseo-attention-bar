import Foundation

enum Formatting {
    /// 「3分前」「2時間前」のような相対表示
    static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "いま" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)時間前" }
        let days = hours / 24
        return "\(days)日前"
    }

    static func reasonLabel(_ agent: AgentSummary) -> String {
        switch agent.bucket {
        case .needsInput:
            if let t = agent.pendingPermissionTitle, !t.isEmpty { return "入力待ち: \(t)" }
            return "入力待ち"
        case .failed:
            if let e = agent.lastError, !e.isEmpty { return "エラー: \(e)" }
            return "エラー"
        case .attention: return "完了・確認待ち"
        case .running: return "実行中"
        case .done: return "確認済み"
        }
    }
}
