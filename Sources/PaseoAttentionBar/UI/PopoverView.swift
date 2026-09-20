import SwiftUI

struct PopoverView: View {
    static let width: CGFloat = 380

    @ObservedObject var client: PaseoClient

    var onOpenAgent: (String) -> Void
    var onQuit: () -> Void

    private var needsInput: [AgentSummary] { client.agents(in: .needsInput) }
    private var failed: [AgentSummary] { client.agents(in: .failed) }
    private var attention: [AgentSummary] { client.agents(in: .attention) }
    private var running: [AgentSummary] { client.agents(in: .running) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if client.connection != .connected {
                disconnectedState
            } else if needsInput.isEmpty && failed.isEmpty && attention.isEmpty && running.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        section("入力待ち", agents: needsInput, tint: .orange, showMarkRead: false)
                        section("エラー", agents: failed, tint: .red, showMarkRead: true)
                        section("完了・確認待ち", agents: attention, tint: .accentColor, showMarkRead: true)
                        section("実行中", agents: running, tint: .secondary, showMarkRead: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 480)
            }

            Divider()
            footer
        }
        .frame(width: PopoverView.width)
        // 子ビューが幅を要求しても、ここで切って popover のサイズに影響させない
        .clipped()
    }

    // MARK: - パーツ

    private var header: some View {
        HStack {
            Text("Paseo 確認待ち")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !attention.isEmpty || !failed.isEmpty {
                Button("すべて既読") { client.clearAllAttention() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("完了・確認待ちとエラーをすべて既読にする（Paseo Desktop で開いたのと同じ扱い）")
            }
            Button {
                client.reconnect()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("再接続")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Circle()
                .fill(client.connection == .connected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(client.connection.label + (client.serverVersion.map { " · v\($0)" } ?? ""))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Paseo を開く") { client.openDesktop() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
            Button("終了") { onQuit() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("確認待ちのタスクはありません")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var disconnectedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(client.connection.label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Paseo Desktop を起動するか `paseo start` でデーモンを立ててください。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func section(_ title: String, agents: [AgentSummary], tint: Color, showMarkRead: Bool) -> some View {
        if !agents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                    Text("\(agents.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(agents) { agent in
                    AgentRow(
                        agent: agent,
                        now: client.tick,
                        showMarkRead: showMarkRead,
                        onOpen: { onOpenAgent(agent.id) },
                        onMarkRead: { client.clearAttention(agentIds: [agent.id]) }
                    )
                }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentSummary
    let now: Date
    let showMarkRead: Bool
    var onOpen: () -> Void
    var onMarkRead: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(agent.displayProject)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(Formatting.relative(agent.attentionDate, now: now))
                    if agent.bucket == .needsInput || agent.bucket == .failed {
                        Text("·")
                        Text(Formatting.reasonLabel(agent))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if showMarkRead && hovering {
                Button {
                    onMarkRead()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("既読にする")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
        .help("Paseo Desktop で開く")
    }
}
