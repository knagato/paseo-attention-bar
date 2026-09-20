import Foundation
import AppKit
import Combine

/// Paseo デーモンの WebSocket（`ws://<host>/ws`）に直接つなぎ、
/// エージェント一覧を購読して `requiresAttention` の変化を追う。
///
/// 手順は CLI（@getpaseo/client）と同じ:
///   1. 接続直後に `{"type":"hello", clientId, clientType, protocolVersion:1, capabilities}` を送る
///      （capabilities に `all_providers` を含めないと一部プロバイダのエージェントが一覧から落ちる）
///   2. サーバから `status: server_info`（serverId 入り）が届く
///   3. `{"type":"session","message":{"type":"fetch_agents_request", subscribe:{...}}}` で一覧＋購読
///   4. 以後 `agent_update`（upsert / remove）と `agent_attention_required` が流れてくる
@MainActor
final class PaseoClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected(reason: String?)
        case connecting
        case connected

        var label: String {
            switch self {
            case .connected: return "接続中"
            case .connecting: return "接続しています…"
            case .disconnected(let reason):
                if let reason, !reason.isEmpty { return "未接続（\(reason)）" }
                return "未接続"
            }
        }
    }

    @Published private(set) var agents: [String: AgentSummary] = [:]
    @Published private(set) var connection: ConnectionState = .disconnected(reason: nil)
    @Published private(set) var serverId: String?
    @Published private(set) var serverVersion: String?
    /// 相対時刻表示を定期的に引き直すための時計
    @Published private(set) var tick = Date()

    private let preferences: Preferences
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    /// 古い接続からのコールバックを捨てるための世代番号
    private var generation = 0
    private var reconnectAttempt = 0
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var tickTimer: Timer?
    private var lastMessageAt = Date()
    private var requestCounter = 0
    private var activeFetchRequestId: String?
    private var receivedFirstPage = false
    private var subscribed = false
    private let subscriptionId = "menubar-attention"

    private static let capabilities: [String: Bool] = [
        "all_providers": true,
        "selective_agent_timeline": true,
        "reasoning_merge_enum": true,
        "custom_mode_icons": true,
        "terminal_reflowable_snapshot": true,
        "provider_subagents": true,
        "project_updates": true,
        "compact_provider_snapshots": true,
        "provider_snapshot_references": true,
        "timeline_replacement_invalidation": true,
        "timeline_notifications": true,
        "plugin_timeline_items": true,
        "workspace_setup_blocked": true,
        "explicit_event_subscriptions": true,
    ]

    init(preferences: Preferences) {
        self.preferences = preferences
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - ライフサイクル

    func start() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
        connect()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        teardownConnection()
        connection = .disconnected(reason: nil)
    }

    /// 手動再接続（右クリックメニュー用）。バックオフをリセットする。
    func reconnect() {
        reconnectAttempt = 0
        teardownConnection()
        connect()
    }

    private func connect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        guard let url = preferences.webSocketURL else {
            connection = .disconnected(reason: "接続先が不正です")
            return
        }
        generation += 1
        let gen = generation
        connection = .connecting
        receivedFirstPage = false
        subscribed = false
        activeFetchRequestId = nil

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        lastMessageAt = Date()
        sendJSON([
            "type": "hello",
            "clientId": preferences.clientId,
            "clientType": "cli",
            "protocolVersion": 1,
            "capabilities": PaseoClient.capabilities,
            "appVersion": "menubar-0.1.0",
        ])
        startReceiving(task: task, generation: gen)
        startPing()
    }

    private func teardownConnection() {
        generation += 1
        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func handleDisconnect(reason: String) {
        // 切断時は前回の一覧を残さない。古い「確認待ち」を見せ続けると誤認するため。
        agents = [:]
        pingTimer?.invalidate()
        pingTimer = nil
        task = nil
        let friendly = friendlyReason(reason)
        connection = .disconnected(reason: friendly)
        scheduleReconnect()
    }

    private func friendlyReason(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("connection refused") || lower.contains("could not connect") {
            return "デーモン停止？"
        }
        if lower.contains("timed out") { return "タイムアウト" }
        return raw
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        let delay = min(30.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.connect() }
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pingTick() }
        }
    }

    private func pingTick() {
        guard task != nil else { return }
        // 70 秒何も来なければ死んだとみなして張り直す
        if Date().timeIntervalSince(lastMessageAt) > 70 {
            teardownConnection()
            handleDisconnect(reason: "応答なし")
            return
        }
        sendJSON(["type": "ping"])
    }

    // MARK: - 送受信

    private func startReceiving(task: URLSessionWebSocketTask, generation: Int) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    guard let self, self.generation == generation else { return }
                    self.lastMessageAt = Date()
                    self.handle(message)
                } catch {
                    guard let self, self.generation == generation else { return }
                    self.handleDisconnect(reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        let gen = generation
        Task { [weak self] in
            do {
                try await task.send(.string(text))
            } catch {
                guard let self, self.generation == gen else { return }
                self.handleDisconnect(reason: error.localizedDescription)
            }
        }
    }

    private func sendSession(_ message: [String: Any]) {
        sendJSON(["type": "session", "message": message])
    }

    private func nextRequestId() -> String {
        requestCounter += 1
        return "menubar-\(requestCounter)-\(Int(Date().timeIntervalSince1970))"
    }

    private func sendFetch(cursor: String? = nil) {
        let requestId = nextRequestId()
        activeFetchRequestId = requestId
        var page: [String: Any] = ["limit": 200]
        if let cursor { page["cursor"] = cursor }
        var message: [String: Any] = [
            "type": "fetch_agents_request",
            "requestId": requestId,
            "filter": ["includeArchived": false],
            "page": page,
        ]
        if !subscribed {
            message["subscribe"] = ["subscriptionId": subscriptionId]
            subscribed = true
        }
        sendSession(message)
    }

    /// 既読にする（Desktop で開いたときと同じ扱い）
    func clearAttention(agentIds: [String]) {
        guard !agentIds.isEmpty else { return }
        sendSession([
            "type": "clear_agent_attention",
            "agentId": agentIds,
            "requestId": nextRequestId(),
        ])
        // 応答を待たずに手元も更新して、クリック直後に消えるようにする
        for id in agentIds {
            agents[id]?.requiresAttention = false
            agents[id]?.attentionReason = nil
        }
    }

    func clearAllAttention() {
        clearAttention(agentIds: agents.values.filter { $0.requiresAttention }.map(\.id))
    }

    /// Paseo Desktop でそのエージェントを開く（`paseo agent open` と同じ deep link）
    func openInDesktop(agentId: String) {
        if let serverId,
           let sid = serverId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let aid = agentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "paseo://h/\(sid)/agent/\(aid)") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "paseo://") {
            NSWorkspace.shared.open(url)
        }
    }

    func openDesktop() {
        if let url = URL(string: "paseo://") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 受信処理

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = root["type"] as? String else { return }

        switch type {
        case "session":
            if let inner = root["message"] as? [String: Any] { handleSessionMessage(inner) }
        case "pong":
            break
        default:
            break
        }
    }

    private func handleSessionMessage(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }
        let payload = msg["payload"] as? [String: Any]

        switch type {
        case "status":
            guard let payload, payload["status"] as? String == "server_info" else { return }
            serverId = payload["serverId"] as? String
            serverVersion = payload["version"] as? String
            connection = .connected
            reconnectAttempt = 0
            sendFetch()

        case "fetch_agents_response":
            guard let payload else { return }
            guard payload["requestId"] as? String == activeFetchRequestId else { return }
            let entries = (payload["entries"] as? [[String: Any]]) ?? []
            var next = receivedFirstPage ? agents : [:]
            for entry in entries {
                guard let agent = entry["agent"] as? [String: Any],
                      let summary = AgentSummary(agent: agent, project: entry["project"] as? [String: Any]) else { continue }
                next[summary.id] = summary
            }
            agents = next
            receivedFirstPage = true
            let pageInfo = payload["pageInfo"] as? [String: Any]
            if pageInfo?["hasMore"] as? Bool == true, let cursor = pageInfo?["nextCursor"] as? String {
                sendFetch(cursor: cursor)
            } else {
                activeFetchRequestId = nil
            }

        case "agent_update":
            guard let payload, let kind = payload["kind"] as? String else { return }
            if kind == "upsert", let agent = payload["agent"] as? [String: Any] {
                if let summary = AgentSummary(agent: agent, project: payload["project"] as? [String: Any]) {
                    if summary.archived {
                        agents.removeValue(forKey: summary.id)
                    } else {
                        // project は upsert に付かないことがあるので、既知なら引き継ぐ
                        var merged = summary
                        if merged.projectName == nil, let known = agents[summary.id] {
                            merged.projectName = known.projectName
                            merged.workspaceName = known.workspaceName
                        }
                        agents[summary.id] = merged
                    }
                }
            } else if kind == "remove", let id = payload["agentId"] as? String {
                agents.removeValue(forKey: id)
            }

        case "agent_attention_required":
            guard let payload, let id = payload["agentId"] as? String else { return }
            // 通常は直後に agent_update も来るが、先にフラグだけ立てておく
            agents[id]?.requiresAttention = true
            agents[id]?.attentionReason = payload["reason"] as? String
            agents[id]?.attentionTimestamp = AgentSummary.parseDate(payload["timestamp"]) ?? Date()

        case "clear_agent_attention_response":
            guard let payload, let list = payload["agents"] as? [[String: Any]] else { return }
            for agent in list {
                if let summary = AgentSummary(agent: agent, project: nil) {
                    var merged = summary
                    if let known = agents[summary.id] {
                        merged.projectName = known.projectName
                        merged.workspaceName = known.workspaceName
                    }
                    agents[summary.id] = merged
                }
            }

        case "rpc_error":
            if let payload {
                NSLog("PaseoAttentionBar rpc_error: %@", String(describing: payload))
            }

        default:
            break
        }
    }

    // MARK: - 集計

    /// 表示対象（closed / archived を除く）
    var visibleAgents: [AgentSummary] {
        agents.values.filter { !$0.archived && $0.status != "closed" }
    }

    func agents(in bucket: AgentBucket) -> [AgentSummary] {
        visibleAgents
            .filter { $0.bucket == bucket }
            .sorted { $0.attentionDate > $1.attentionDate }
    }

    var counts: (needsInput: Int, failed: Int, attention: Int, running: Int) {
        var c = (needsInput: 0, failed: 0, attention: 0, running: 0)
        for a in visibleAgents {
            switch a.bucket {
            case .needsInput: c.needsInput += 1
            case .failed: c.failed += 1
            case .attention: c.attention += 1
            case .running: c.running += 1
            case .done: break
            }
        }
        return c
    }
}
