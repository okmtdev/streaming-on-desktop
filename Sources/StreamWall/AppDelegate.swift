import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StreamStore()
    private let appState = AppState()
    private let loc = Localizer.shared

    private var windows: [UUID: StreamWindowController] = [:]
    private var statusItem: NSStatusItem?
    private var controlPanelWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onStructuralChange = { [weak self] in
            self?.syncWindows()
        }

        // 配置モードの切替を全ウィンドウへ反映。
        appState.$editMode
            .sink { [weak self] mode in
                guard let self else { return }
                self.windows.values.forEach { $0.applyMode(editMode: mode) }
                self.updateControlPanelLevel()
            }
            .store(in: &cancellables)

        // 言語変更でメニューを作り直す。
        loc.$language
            .sink { [weak self] _ in
                self?.rebuildMenus()
            }
            .store(in: &cancellables)

        // 「すべて再読み込み」。
        NotificationCenter.default.publisher(for: .reloadAllStreams)
            .sink { [weak self] _ in
                self?.windows.values.forEach { $0.reload() }
            }
            .store(in: &cancellables)

        // 単体の再読み込み。
        NotificationCenter.default.publisher(for: .reloadStream)
            .sink { [weak self] note in
                if let id = note.object as? UUID {
                    self?.windows[id]?.reload()
                }
            }
            .store(in: &cancellables)

        // 設定画面を閉じる（アプリは終了しない）。
        NotificationCenter.default.publisher(for: .closeControlPanel)
            .sink { [weak self] _ in
                self?.controlPanelWindow?.orderOut(nil)
            }
            .store(in: &cancellables)

        // スリープ復帰時に全ストリームを再読み込み（止まった映像を復活させる）。
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.windows.values.forEach { $0.reload() }
            }
            .store(in: &cancellables)

        buildMainMenu()
        setupStatusItem()
        syncWindows()

        // 初回起動でストリームが無ければ案内のため管理画面を開く。
        if store.streams.isEmpty {
            openControlPanel()
        }
    }

    // MARK: - メインメニュー（編集メニューで Cmd+C/V/X を有効化）

    /// LSUIElement アプリでも、メインメニューに「編集」項目があれば
    /// テキストフィールドでコピー&ペーストのキー操作が効くようになる。
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // アプリメニュー（先頭・タイトルは表示されない）
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: loc.t("menu_quit"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 編集メニュー
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: loc.t("edit_menu_title"))
        editMenu.addItem(withTitle: loc.t("edit_undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: loc.t("edit_redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: loc.t("edit_cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: loc.t("edit_copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: loc.t("edit_paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: loc.t("edit_select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - メニューバー（ステータスアイコン）

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle",
                                   accessibilityDescription: "StreamWall")
        }
        item.menu = makeStatusMenu()
        self.statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: loc.t("menu_open_panel"), action: #selector(openControlPanel), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: loc.t("menu_edit_mode"), action: #selector(toggleEditMode), keyEquivalent: "e"))
        menu.addItem(withTitle: loc.t("menu_reload_all"), action: #selector(reloadAll), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: loc.t("menu_quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        return menu
    }

    private func rebuildMenus() {
        buildMainMenu()
        statusItem?.menu = makeStatusMenu()
        controlPanelWindow?.title = "StreamWall"
    }

    @objc private func openControlPanel() {
        if controlPanelWindow == nil {
            let view = ControlPanel(store: store, appState: appState, loc: loc)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "StreamWall"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            controlPanelWindow = window
        }
        updateControlPanelLevel()
        NSApp.activate(ignoringOtherApps: true)
        controlPanelWindow?.makeKeyAndOrderFront(nil)
    }

    /// 配置モード中はストリーム窓が前面（.floating）に出るので、
    /// 設定画面はそれより上の階層に上げて隠れないようにする。
    private func updateControlPanelLevel() {
        guard let window = controlPanelWindow else { return }
        if appState.editMode {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.orderFront(nil)
        } else {
            window.level = .normal
        }
    }

    @objc private func toggleEditMode() {
        appState.editMode.toggle()
    }

    @objc private func reloadAll() {
        windows.values.forEach { $0.reload() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - ウィンドウ同期

    /// store のストリーム一覧に合わせてウィンドウを作成・更新・削除する。
    private func syncWindows() {
        let ids = Set(store.streams.map { $0.id })

        for (id, controller) in windows where !ids.contains(id) {
            controller.closeWindow()
            windows[id] = nil
        }

        for stream in store.streams {
            if let controller = windows[stream.id] {
                controller.update(stream: stream)
            } else {
                let controller = StreamWindowController(stream: stream, store: store)
                windows[stream.id] = controller
                controller.applyMode(editMode: appState.editMode)
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let editItem = menu.items.first(where: { $0.action == #selector(toggleEditMode) }) {
            editItem.state = appState.editMode ? .on : .off
        }
    }
}
