import Foundation
import AppKit

/// 1本のストリーム（URL と配置情報）を表すモデル。
struct Stream: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    /// グローバル座標（全ディスプレイをまたぐ座標系・左下原点）でのウィンドウ枠。
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.size.width
            height = newValue.size.height
        }
    }

    init(id: UUID = UUID(), url: String, frame: CGRect) {
        self.id = id
        self.url = url
        self.x = frame.origin.x
        self.y = frame.origin.y
        self.width = frame.size.width
        self.height = frame.size.height
    }
}

/// ストリーム一覧の永続化と編集を担う。
final class StreamStore: ObservableObject {
    @Published private(set) var streams: [Stream] = []

    /// 追加・削除・URL変更など「ウィンドウの構成が変わる」操作の後に呼ばれる。
    /// （位置・サイズだけの変更では呼ばれない）
    var onStructuralChange: (() -> Void)?

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("StreamWall", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("streams.json")
        load()
    }

    // MARK: - 編集

    func add(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stream = Stream(url: trimmed, frame: Self.defaultFrame())
        streams.append(stream)
        save()
        onStructuralChange?()
    }

    func remove(id: UUID) {
        streams.removeAll { $0.id == id }
        save()
        onStructuralChange?()
    }

    func updateURL(id: UUID, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = streams.firstIndex(where: { $0.id == id }) else { return }
        guard streams[idx].url != trimmed, !trimmed.isEmpty else { return }
        streams[idx].url = trimmed
        save()
        onStructuralChange?()
    }

    /// 位置・サイズだけの更新。構成変更通知は出さない（ウィンドウ再生成を避けるため）。
    func setFrame(id: UUID, frame: CGRect) {
        guard let idx = streams.firstIndex(where: { $0.id == id }) else { return }
        guard streams[idx].frame != frame else { return }
        streams[idx].frame = frame
        save()
    }

    // MARK: - 永続化

    private func save() {
        do {
            let data = try JSONEncoder().encode(streams)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("StreamWall: 保存に失敗: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Stream].self, from: data) {
            streams = decoded
        }
    }

    // MARK: - ヘルパー

    /// 新規ウィンドウの初期枠。メインディスプレイの中央に 480x270 で置く。
    static func defaultFrame() -> CGRect {
        let size = CGSize(width: 480, height: 270)
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            return CGRect(
                x: v.midX - size.width / 2,
                y: v.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
        return CGRect(origin: .zero, size: size)
    }
}
