import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// メニューバー常駐なので Dock アイコンもメニューも出さない。
// （Info.plist の LSUIElement と合わせて二重に指定しておく）
app.setActivationPolicy(.accessory)
app.run()
