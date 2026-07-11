import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Dock アイコンを出さず、メニューバー常駐アプリとして動かす。
app.setActivationPolicy(.accessory)
app.run()
