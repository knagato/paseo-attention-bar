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

    init() {
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
