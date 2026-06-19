import AppKit
import WebKit

/// 1本のストリームを表示するウィンドウを管理する。
/// 通常時はデスクトップ階層（壁紙レイヤー）に固定され、他アプリの後ろで垂れ流す。
/// 配置モード時は前面の通常ウィンドウになり、ドラッグ移動・リサイズ・別ディスプレイへの移動ができる。
final class StreamWindowController: NSObject, NSWindowDelegate {
    let streamID: UUID
    private(set) var url: String

    private let store: StreamStore
    private let window: NSWindow
    private let webView: WKWebView

    /// 削除に伴うプログラム的なクローズかどうか（× ボタン押下と区別するため）。
    private var isClosingProgrammatically = false

    init(stream: Stream, store: StreamStore) {
        self.streamID = stream.id
        self.url = stream.url
        self.store = store

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // 白いちらつきを防ぐ
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
        window.title = stream.url
        window.setFrame(stream.frame, display: true)

        loadStream(url: stream.url)
    }

    // MARK: - 表示

    func show() {
        window.orderFront(nil)
    }

    func closeWindow() {
        isClosingProgrammatically = true
        window.close()
    }

    /// store 側のモデル更新を反映する。URL が変わったときだけ再読み込みする。
    func update(stream: Stream) {
        if stream.url != url {
            url = stream.url
            window.title = stream.url
            loadStream(url: stream.url)
        }
    }

    // MARK: - モード切替

    /// editMode == false: 壁紙レイヤーに固定（クリックは透過、操作不可）。
    /// editMode == true : 前面の通常ウィンドウ（移動・リサイズ・削除可）。
    func applyMode(editMode: Bool) {
        let frame = window.frame
        if editMode {
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.level = .floating
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            window.title = url
            window.delegate = self
            window.contentView = webView
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
        window.orderFront(nil)
    }

    // MARK: - 読み込み

    private func loadStream(url: String) {
        webView.loadHTMLString(Self.makeHTML(urlString: url), baseURL: nil)
    }

    func reload() {
        loadStream(url: url)
    }

    /// MJPEG（motion 等）を <img> で表示し、切断時は自動で再接続する HTML を作る。
    private static func makeHTML(urlString: String) -> String {
        let escaped = urlString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          #v { width: 100vw; height: 100vh; object-fit: contain; display: block; }
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
