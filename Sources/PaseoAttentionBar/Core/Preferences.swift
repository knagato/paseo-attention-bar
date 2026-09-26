import Foundation
import Combine

/// 設定は少ないので UserDefaults に直接置く。
@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let host = "daemonHost"
        static let showRunning = "showRunningCount"
        static let clientId = "paseoClientId"
    }

    /// デーモンの host:port。`~/.paseo/config.json` の `daemon.listen` と同じ形式。
    @Published var daemonHost: String {
        didSet { defaults.set(daemonHost, forKey: Key.host) }
    }

    /// メニューバーに実行中の件数（▶n）も出すか
    @Published var showRunningCount: Bool {
        didSet { defaults.set(showRunningCount, forKey: Key.showRunning) }
    }

    /// デーモンへの hello で名乗る clientId。初回に生成して固定する。
    let clientId: String

    /// 0.1.0 までのバンドル ID。UserDefaults はバンドル ID ごとの領域に入るので、
    /// ID を変えた後の初回起動で旧領域の設定（clientId、メニューバー上の位置など）を引き継ぐ。
    private static let legacyDomain = "com.knagato.PaseoAttentionBar"

    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        guard Bundle.main.bundleIdentifier != legacyDomain,
              defaults.string(forKey: Key.clientId) == nil,
              let legacy = defaults.persistentDomain(forName: legacyDomain) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    init() {
        Self.migrateLegacyDefaults(into: defaults)
        daemonHost = defaults.string(forKey: Key.host) ?? "127.0.0.1:6767"
        showRunningCount = defaults.object(forKey: Key.showRunning) as? Bool ?? true
        if let existing = defaults.string(forKey: Key.clientId) {
            clientId = existing
        } else {
            let generated = "menubar-" + UUID().uuidString.lowercased()
            defaults.set(generated, forKey: Key.clientId)
            clientId = generated
        }
    }

    var webSocketURL: URL? {
        var host = daemonHost.trimmingCharacters(in: .whitespaces)
        if host.isEmpty { host = "127.0.0.1:6767" }
        if host.hasPrefix("ws://") || host.hasPrefix("wss://") {
            return URL(string: host.hasSuffix("/ws") ? host : host + "/ws")
        }
        return URL(string: "ws://\(host)/ws")
    }
}
