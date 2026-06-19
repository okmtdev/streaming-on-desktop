import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StreamStore()
    private let appState = AppState()

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
            }
            .store(in: &cancellables)

        // 「すべて再読み込み」。
        NotificationCenter.default.publisher(for: .reloadAllStreams)
            .sink { [weak self] _ in
                self?.windows.values.forEach { $0.reload() }
            }
            .store(in: &cancellables)

        setupStatusItem()
        syncWindows()

        // 初回起動でストリームが無ければ案内のため管理画面を開く。
        if store.streams.isEmpty {
            openControlPanel()
        }
    }

    // MARK: - メニューバー

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle",
                                   accessibilityDescription: "StreamWall")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "管理画面を開く…", action: #selector(openControlPanel), keyEquivalent: "o")
        menu.addItem(.separator())

        let editItem = NSMenuItem(title: "配置モード", action: #selector(toggleEditMode), keyEquivalent: "e")
        menu.addItem(editItem)

        menu.addItem(withTitle: "すべて再読み込み", action: #selector(reloadAll), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(quit), keyEquivalent: "q")

        menu.items.forEach { $0.target = self }
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openControlPanel() {
        if controlPanelWindow == nil {
            let view = ControlPanel(store: store, appState: appState)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "StreamWall"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            controlPanelWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        controlPanelWindow?.makeKeyAndOrderFront(nil)
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
                controller.show()
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
