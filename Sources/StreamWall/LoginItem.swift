import Foundation
import ServiceManagement

/// ログイン時の自動起動を管理する（macOS 13+ の SMAppService を使用）。
/// 旧来の login item ヘルパー（別バイナリ）が不要で、アプリ単体で登録/解除できる。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("StreamWall: ログイン項目の更新に失敗: \(error)")
            return false
        }
    }
}
