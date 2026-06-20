import Foundation
import AppKit

/// 映像のはめ込み方。CSS の object-fit に対応する。
enum FitMode: String, Codable, CaseIterable, Identifiable {
    case contain // 全体表示（はみ出さない）
    case cover   // 切り抜き（枠いっぱい・はみ出しトリミング）
    case fill    // 引き伸ばし（縦横比を無視）
    var id: String { rawValue }
}

/// 1本のストリーム（URL と配置・表示設定）を表すモデル。
struct Stream: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    var name: String
    /// グローバル座標（全ディスプレイをまたぐ座標系・左下原点）でのウィンドウ枠。
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var enabled: Bool
    var fit: FitMode
    var opacity: Double
    /// 定期再読み込みの間隔（分）。0 ならオフ。
    var reloadMinutes: Int

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.size.width
            height = newValue.size.height
        }
    }

    /// 一覧などに出す表示名。name が空なら URL を使う。
    var displayName: String {
        name.isEmpty ? url : name
    }

    init(id: UUID = UUID(), url: String, name: String = "", frame: CGRect,
         enabled: Bool = true, fit: FitMode = .contain, opacity: Double = 1.0,
         reloadMinutes: Int = 0) {
        self.id = id
        self.url = url
        self.name = name
        self.x = frame.origin.x
        self.y = frame.origin.y
        self.width = frame.size.width
        self.height = frame.size.height
        self.enabled = enabled
        self.fit = fit
        self.opacity = opacity
        self.reloadMinutes = reloadMinutes
    }

    // 既存の streams.json（新フィールドが無い）も読めるよう、欠損キーは既定値で補う。
    enum CodingKeys: String, CodingKey {
        case id, url, name, x, y, width, height, enabled, fit, opacity, reloadMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        fit = try c.decodeIfPresent(FitMode.self, forKey: .fit) ?? .contain
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        reloadMinutes = try c.decodeIfPresent(Int.self, forKey: .reloadMinutes) ?? 0
    }
}

/// ストリーム一覧の永続化と編集を担う。
final class StreamStore: ObservableObject {
    @Published private(set) var streams: [Stream] = []

    /// 追加・削除・プロパティ変更の後に呼ばれる（ウィンドウへ反映するため）。
    /// 位置・サイズだけの変更（ウィンドウ→モデル方向）では呼ばれない。
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
        streams.append(Stream(url: trimmed, frame: Self.defaultFrame()))
        save()
        onStructuralChange?()
    }

    func remove(id: UUID) {
        streams.removeAll { $0.id == id }
        save()
        onStructuralChange?()
    }

    /// プロパティ（URL・名前・表示・fit・不透明度）の更新。
    func update(_ stream: Stream) {
        guard let idx = streams.firstIndex(where: { $0.id == stream.id }) else { return }
        guard streams[idx] != stream else { return }
        streams[idx] = stream
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
