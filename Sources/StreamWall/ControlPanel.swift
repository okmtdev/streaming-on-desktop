import SwiftUI

/// アプリ全体の状態（配置モードのON/OFF）。
final class AppState: ObservableObject {
    @Published var editMode: Bool = false
}

/// メニューバーから開く管理画面。URLの追加・編集・削除、各種設定、配置モードの切替を行う。
struct ControlPanel: View {
    @ObservedObject var store: StreamStore
    @ObservedObject var appState: AppState
    @ObservedObject var loc: Localizer

    @State private var newURL: String = ""
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("StreamWall").font(.headline)
                Spacer()
                Picker(loc.t("panel_language"), selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName(loc)).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("panel_arrange"))
                    Text(appState.editMode ? loc.t("panel_arrange_on") : loc.t("panel_arrange_off"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $appState.editMode)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .frame(minHeight: 44)

            Toggle(loc.t("panel_launch_at_login"), isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { newValue in
                    LoginItem.set(newValue)
                    // 失敗時は実際の状態へ戻す。
                    launchAtLogin = LoginItem.isEnabled
                }

            Divider()

            HStack {
                TextField(loc.t("panel_url_ph"), text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addStream)
                Button(loc.t("panel_add"), action: addStream)
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if store.streams.isEmpty {
                Text(loc.t("panel_empty"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(store.streams) { stream in
                            StreamRow(store: store, loc: loc, streamID: stream.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 240, maxHeight: 460)
            }

            Divider()

            HStack {
                Button(loc.t("menu_reload_all")) {
                    NotificationCenter.default.post(name: .reloadAllStreams, object: nil)
                }
                Spacer()
                Button(loc.t("panel_close")) {
                    NotificationCenter.default.post(name: .closeControlPanel, object: nil)
                }
                .keyboardShortcut(.cancelAction)
                Button(loc.t("menu_quit")) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func addStream() {
        store.add(url: newURL)
        newURL = ""
    }
}

/// 1つのストリームの設定行（名前・URL・表示ON/OFF・fit・不透明度・操作）。
private struct StreamRow: View {
    @ObservedObject var store: StreamStore
    @ObservedObject var loc: Localizer
    let streamID: UUID

    @State private var nameText: String = ""
    @State private var urlText: String = ""
    @FocusState private var urlFocused: Bool

    /// 常に store の最新値を参照する。
    private var current: Stream? {
        store.streams.first { $0.id == streamID }
    }

    var body: some View {
        GroupBox {
            if let stream = current {
                VStack(spacing: 10) {
                    HStack {
                        // 名前は入力のたびに保存する（Enter を押し忘れても消えない）。
                        TextField(loc.t("panel_name_ph"), text: $nameText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: nameText) { _ in commitName(stream) }
                        Toggle(loc.t("panel_show"), isOn: enabledBinding(stream))
                            .toggleStyle(.checkbox)
                    }

                    HStack {
                        // URL は入力中の再接続を避けるため、確定 or フォーカスを外した時に保存。
                        TextField("URL", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .focused($urlFocused)
                            .onSubmit { commitURL(stream) }
                            .onChange(of: urlFocused) { focused in
                                if !focused { commitURL(stream) }
                            }
                        Button {
                            NotificationCenter.default.post(name: .reloadStream, object: streamID)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(loc.t("panel_reload"))
                        Button {
                            store.remove(id: streamID)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(loc.t("panel_delete"))
                    }

                    HStack(spacing: 12) {
                        Picker(loc.t("panel_fit"), selection: fitBinding(stream)) {
                            Text(loc.t("fit_contain")).tag(FitMode.contain)
                            Text(loc.t("fit_cover")).tag(FitMode.cover)
                            Text(loc.t("fit_fill")).tag(FitMode.fill)
                        }
                        .frame(width: 180)

                        Text(loc.t("panel_opacity")).font(.caption)
                        Slider(value: opacityBinding(stream), in: 0.2...1.0)
                    }

                    HStack(spacing: 12) {
                        Toggle(loc.t("panel_auto_reload"), isOn: autoReloadBinding(stream))
                            .toggleStyle(.checkbox)
                        if (current?.reloadMinutes ?? 0) > 0 {
                            Stepper(value: minutesBinding(stream), in: 1...1440) {
                                Text("\(current?.reloadMinutes ?? 0) \(loc.t("panel_minutes"))")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .frame(width: 150)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 4)
                .onAppear {
                    nameText = stream.name
                    urlText = stream.url
                }
            }
        }
    }

    // MARK: - コミット / バインディング

    private func commitName(_ stream: Stream) {
        var s = current ?? stream
        s.name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(s)
    }

    private func commitURL(_ stream: Stream) {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var s = current ?? stream
        s.url = trimmed
        store.update(s)
    }

    private func enabledBinding(_ stream: Stream) -> Binding<Bool> {
        Binding(
            get: { current?.enabled ?? stream.enabled },
            set: { var s = current ?? stream; s.enabled = $0; store.update(s) }
        )
    }

    private func fitBinding(_ stream: Stream) -> Binding<FitMode> {
        Binding(
            get: { current?.fit ?? stream.fit },
            set: { var s = current ?? stream; s.fit = $0; store.update(s) }
        )
    }

    private func opacityBinding(_ stream: Stream) -> Binding<Double> {
        Binding(
            get: { current?.opacity ?? stream.opacity },
            set: { var s = current ?? stream; s.opacity = $0; store.update(s) }
        )
    }

    /// 定期再読み込みの ON/OFF。ON にしたら既定 5 分。
    private func autoReloadBinding(_ stream: Stream) -> Binding<Bool> {
        Binding(
            get: { (current?.reloadMinutes ?? stream.reloadMinutes) > 0 },
            set: { on in
                var s = current ?? stream
                s.reloadMinutes = on ? 5 : 0
                store.update(s)
            }
        )
    }

    private func minutesBinding(_ stream: Stream) -> Binding<Int> {
        Binding(
            get: { max(1, current?.reloadMinutes ?? stream.reloadMinutes) },
            set: { var s = current ?? stream; s.reloadMinutes = $0; store.update(s) }
        )
    }
}

extension Notification.Name {
    static let reloadAllStreams = Notification.Name("StreamWall.reloadAllStreams")
    static let reloadStream = Notification.Name("StreamWall.reloadStream")
    static let closeControlPanel = Notification.Name("StreamWall.closeControlPanel")
}
