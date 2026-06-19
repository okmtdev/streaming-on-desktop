import SwiftUI

/// アプリ全体の状態（配置モードのON/OFF）。
final class AppState: ObservableObject {
    @Published var editMode: Bool = false
}

/// メニューバーから開く管理画面。URLの追加・編集・削除と配置モードの切替を行う。
struct ControlPanel: View {
    @ObservedObject var store: StreamStore
    @ObservedObject var appState: AppState

    @State private var newURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("StreamWall")
                .font(.headline)

            Toggle(isOn: $appState.editMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("配置モード")
                    Text(appState.editMode
                         ? "前面に出ています。ドラッグで移動・端でリサイズ・別ディスプレイへ移動できます。"
                         : "壁紙レイヤーに固定中（他アプリの後ろで再生）。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            HStack {
                TextField("http://192.168.1.4:8081", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addStream)
                Button("追加", action: addStream)
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if store.streams.isEmpty {
                Text("ストリームがまだありません。上のURL欄に motion のアドレスを入れて「追加」してください。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.streams) { stream in
                            StreamRow(store: store, stream: stream)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider()

            HStack {
                Button("すべて再読み込み") {
                    NotificationCenter.default.post(name: .reloadAllStreams, object: nil)
                }
                Spacer()
                Button("終了") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func addStream() {
        store.add(url: newURL)
        newURL = ""
    }
}

/// 1行（URL編集 + 削除）。
private struct StreamRow: View {
    @ObservedObject var store: StreamStore
    let stream: Stream

    @State private var text: String = ""

    var body: some View {
        HStack {
            TextField("URL", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.updateURL(id: stream.id, url: text) }
            Button {
                store.remove(id: stream.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("削除")
        }
        .onAppear { text = stream.url }
    }
}

extension Notification.Name {
    static let reloadAllStreams = Notification.Name("StreamWall.reloadAllStreams")
}
