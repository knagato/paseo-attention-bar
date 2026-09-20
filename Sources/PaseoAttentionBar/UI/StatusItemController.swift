import AppKit
import Combine
import SwiftUI

/// メニューバーの `NSStatusItem` を管理する。
/// タイトルに色を付けたいので `MenuBarExtra` ではなく AppKit を直接使う。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let preferences: Preferences
    private let client: PaseoClient
    private var cancellables = Set<AnyCancellable>()

    init(preferences: Preferences, client: PaseoClient) {
        self.preferences = preferences
        self.client = client
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // これを設定しないと ⌘ドラッグで並び替えた位置が再起動のたびに失われる。
        self.statusItem.autosaveName = "PaseoAttentionBarStatusItem"

        configureButton()
        configurePopover()

        client.objectWillChange
            .merge(with: preferences.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)

        updateTitle()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        let root = PopoverView(
            client: client,
            onOpenAgent: { [weak self] id in
                self?.closePopover()
                self?.client.openInDesktop(agentId: id)
            },
            onQuit: { NSApp.terminate(nil) }
        )
        popover.contentViewController = NSHostingController(rootView: root)
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return togglePopover() }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - 右クリックメニュー

    private func showContextMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: client.connection.label, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Paseo を開く", action: #selector(openDesktop), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "すべて既読にする", action: #selector(clearAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "再接続", action: #selector(reconnect), keyEquivalent: "r").target = self
        menu.addItem(.separator())

        let running = NSMenuItem(title: "実行中の件数も表示", action: #selector(toggleRunning), keyEquivalent: "")
        running.target = self
        running.state = preferences.showRunningCount ? .on : .off
        menu.addItem(running)

        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isSupported
        menu.addItem(login)

        menu.addItem(withTitle: "接続先を変更…（\(preferences.daemonHost)）", action: #selector(editHost), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "PaseoAttentionBar を終了", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDesktop() { client.openDesktop() }
    @objc private func clearAll() { client.clearAllAttention() }
    @objc private func reconnect() { client.reconnect() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleRunning() {
        preferences.showRunningCount.toggle()
    }

    @objc private func toggleLoginItem() {
        if let message = LoginItem.setEnabled(!LoginItem.isEnabled) {
            let alert = NSAlert()
            alert.messageText = "ログイン時に起動"
            alert.informativeText = message
            alert.runModal()
        }
    }

    @objc private func editHost() {
        let alert = NSAlert()
        alert.messageText = "Paseo デーモンの接続先"
        alert.informativeText = "host:port（既定 127.0.0.1:6767）。~/.paseo/config.json の daemon.listen と同じ値。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = preferences.daemonHost
        alert.accessoryView = field
        alert.addButton(withTitle: "接続")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespaces)
            preferences.daemonHost = value.isEmpty ? "127.0.0.1:6767" : value
            client.reconnect()
        }
    }

    // MARK: - ポップオーバー

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - タイトル生成

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let counts = client.counts
        let pending = counts.needsInput + counts.failed + counts.attention

        let symbolName: String
        switch client.connection {
        case .connected: symbolName = pending > 0 ? "tray.full" : "tray"
        case .connecting, .disconnected: symbolName = "tray.and.arrow.down"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Paseo")
        image?.isTemplate = true
        button.image = image
        button.attributedTitle = makeTitle(counts: counts)
        button.toolTip = tooltip(counts: counts)
    }

    private func makeTitle(counts: (needsInput: Int, failed: Int, attention: Int, running: Int)) -> NSAttributedString {
        // メニューバーは壁紙の上に半透明で描かれるため、secondary のような半透明カラーは
        // 背景に沈んで読めなくなる。意味色（橙・赤）以外は labelColor に統一し、
        // 強弱はフォントサイズで付ける。
        let result = NSMutableAttributedString()
        let strong = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let weak = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        func append(_ text: String, color: NSColor, font: NSFont) {
            if result.length > 0 { result.append(NSAttributedString(string: " ")) }
            result.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: color, .font: font,
            ]))
        }

        if case .disconnected = client.connection {
            append("—", color: .labelColor, font: weak)
            return result
        }
        if counts.needsInput > 0 { append("?\(counts.needsInput)", color: .systemOrange, font: strong) }
        if counts.failed > 0 { append("!\(counts.failed)", color: .systemRed, font: strong) }
        if counts.attention > 0 { append("✓\(counts.attention)", color: .labelColor, font: strong) }
        if preferences.showRunningCount && counts.running > 0 {
            append("▶\(counts.running)", color: .labelColor, font: weak)
        }
        if result.length > 0 {
            // アイコンと文字の間隔
            result.insert(NSAttributedString(string: " "), at: 0)
        }
        return result
    }

    private func tooltip(counts: (needsInput: Int, failed: Int, attention: Int, running: Int)) -> String {
        var parts: [String] = [client.connection.label]
        if counts.needsInput > 0 { parts.append("入力待ち \(counts.needsInput)") }
        if counts.failed > 0 { parts.append("エラー \(counts.failed)") }
        if counts.attention > 0 { parts.append("完了・確認待ち \(counts.attention)") }
        if counts.running > 0 { parts.append("実行中 \(counts.running)") }
        return parts.joined(separator: " / ")
    }
}
