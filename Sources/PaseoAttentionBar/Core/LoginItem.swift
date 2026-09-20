import Foundation
import ServiceManagement

/// 「ログイン時に起動」の登録。`SMAppService` は .app バンドルとして
/// 起動している場合のみ機能するので、`swift run` 直起動では無効扱いにする。
enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 成功したら nil、失敗したらユーザに見せるメッセージを返す。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isSupported else {
            return ".app として起動していないため設定できません（make install で /Applications に配置してください）"
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "ログイン項目の変更に失敗しました: \(error.localizedDescription)"
        }
    }
}
