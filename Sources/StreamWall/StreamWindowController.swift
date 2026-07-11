import AppKit
import WebKit

/// 1本のストリームを表示するウィンドウを管理する。
/// 通常時はデスクトップ階層（壁紙レイヤー）に固定され、他アプリの後ろで垂れ流す。
/// 配置モード時は前面の通常ウィンドウになり、ドラッグ移動・リサイズ・別ディスプレイへの移動ができる。
final class StreamWindowController: NSObject, NSWindowDelegate {
    let streamID: UUID

    private let store: StreamStore
    private let window: NSWindow
    private let webView: WKWebView

    /// 現在反映済みのモデル（差分判定に使う）。
    private var stream: Stream
    private var editMode: Bool = false
    private var reloadTimer: Timer?

    /// 削除に伴うプログラム的なクローズかどうか（× ボタン押下と区別するため）。
    private var isClosingProgrammatically = false

    init(stream: Stream, store: StreamStore) {
        self.streamID = stream.id
        self.stream = stream
        self.store = store

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        // 公開APIで背景を黒くし、読み込み時の白いちらつきを防ぐ（App Store審査対応）。
        webView.underPageBackgroundColor = .black
        self.webView = webView

        self.window = NSWindow(
            contentRect: stream.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.delegate = self
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.title = stream.displayName
        window.alphaValue = stream.opacity
        window.setFrame(stream.frame, display: true)

        loadStream()
        updateReloadTimer()
    }

    // MARK: - 表示

    func show() {
        applyVisibility()
    }

    func closeWindow() {
        isClosingProgrammatically = true
        reloadTimer?.invalidate()
        reloadTimer = nil
        window.close()
    }

    /// store 側のモデル更新を、変わった項目だけ反映する。
    func update(stream new: Stream) {
        let old = stream
        stream = new

        if new.url != old.url || new.fit != old.fit {
            loadStream()
        }
        if new.opacity != old.opacity {
            window.alphaValue = new.opacity
        }
        if new.displayName != old.displayName {
            window.title = new.displayName
        }
        if new.enabled != old.enabled {
            applyVisibility()
        }
        if new.reloadMinutes != old.reloadMinutes {
            updateReloadTimer()
        }
    }

    // MARK: - モード切替

    /// editMode == false: 壁紙レイヤーに固定（クリックは透過、操作不可）。
    /// editMode == true : 前面の通常ウィンドウ（移動・リサイズ・削除可）。
    func applyMode(editMode: Bool) {
        self.editMode = editMode
        let frame = window.frame
        if editMode {
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.level = .floating
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            window.title = stream.displayName
        } else {
            window.styleMask = [.borderless]
            // デスクトップ（壁紙）のすぐ上、アイコンより下の階層。
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.hasShadow = false
        }
        // styleMask の変更で枠が変わるので元の位置・サイズを復元する。
        window.setFrame(frame, display: true)
        applyVisibility()
    }

    /// enabled と editMode に応じて表示/非表示を決める。
    /// 非表示ストリームでも配置モード中は見えるようにして、配置や削除をできるようにする。
    private func applyVisibility() {
        if stream.enabled || editMode {
            window.orderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: - 読み込み

    private func loadStream() {
        webView.loadHTMLString(Self.makeHTML(urlString: stream.url, fit: stream.fit), baseURL: nil)
    }

    func reload() {
        loadStream()
    }

    /// 定期再読み込みタイマーを現在の設定に合わせて張り直す。
    private func updateReloadTimer() {
        reloadTimer?.invalidate()
        reloadTimer = nil
        let minutes = stream.reloadMinutes
        guard minutes > 0 else { return }
        let timer = Timer(timeInterval: Double(minutes) * 60.0, repeats: true) { [weak self] _ in
            self?.reload()
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        reloadTimer = timer
    }

    /// MJPEG（motion 等）を <img> で表示し、切断時は自動で再接続する HTML を作る。
    private static func makeHTML(urlString: String, fit: FitMode) -> String {
        let escaped = urlString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let objectFit: String
        switch fit {
        case .contain: objectFit = "contain"
        case .cover: objectFit = "cover"
        case .fill: objectFit = "fill"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          #v { width: 100vw; height: 100vh; object-fit: \(objectFit); display: block; }
        </style>
        </head>
        <body>
          <img id="v" src="\(escaped)">
          <script>
            var img = document.getElementById('v');
            var base = "\(escaped)";
            img.onerror = function () {
              setTimeout(function () {
                img.src = base + (base.indexOf('?') >= 0 ? '&' : '?') + '_r=' + Date.now();
              }, 3000);
            };
          </script>
        </body>
        </html>
        """
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        store.setFrame(id: streamID, frame: window.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        store.setFrame(id: streamID, frame: window.frame)
    }

    /// 配置モードで × を押したら、そのストリームを削除する。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingProgrammatically {
            return true
        }
        store.remove(id: streamID) // → onStructuralChange 経由で closeWindow() が呼ばれる
        return false
    }
}
