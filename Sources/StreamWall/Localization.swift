import Foundation
import Combine

/// 対応言語。auto は OS の優先言語から自動選択する。
enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, en, ja, ko, pt
    var id: String { rawValue }

    /// ピッカーに出す表示名。
    func displayName(_ loc: Localizer) -> String {
        switch self {
        case .auto: return loc.t("lang_auto")
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .pt: return "Português"
        }
    }
}

/// 簡易ローカライズ。.app バンドルへの .lproj 同梱を避けるため、文言はコード内に保持する。
final class Localizer: ObservableObject {
    static let shared = Localizer()

    private let key = "StreamWall.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppLanguage.auto.rawValue
        language = AppLanguage(rawValue: raw) ?? .auto
    }

    /// auto の場合は OS の優先言語から対応言語を選ぶ。該当が無ければ英語。
    private var effective: AppLanguage {
        if language != .auto { return language }
        for code in Locale.preferredLanguages {
            let lc = code.lowercased()
            if lc.hasPrefix("ja") { return .ja }
            if lc.hasPrefix("ko") { return .ko }
            if lc.hasPrefix("pt") { return .pt }
            if lc.hasPrefix("en") { return .en }
        }
        return .en
    }

    func t(_ key: String) -> String {
        Localizer.table[effective.rawValue]?[key]
            ?? Localizer.table["en"]?[key]
            ?? key
    }

    private static let table: [String: [String: String]] = [
        "en": [
            "menu_open_panel": "Open Control Panel…",
            "menu_edit_mode": "Arrange Mode",
            "menu_reload_all": "Reload All",
            "menu_quit": "Quit",
            "edit_menu_title": "Edit",
            "edit_undo": "Undo",
            "edit_redo": "Redo",
            "edit_cut": "Cut",
            "edit_copy": "Copy",
            "edit_paste": "Paste",
            "edit_select_all": "Select All",
            "panel_arrange": "Arrange mode",
            "panel_arrange_on": "Windows are in front. Drag to move, drag edges to resize, move across displays.",
            "panel_arrange_off": "Pinned to the wallpaper layer (playing behind other apps).",
            "panel_add": "Add",
            "panel_url_ph": "http://192.168.1.4:8081",
            "panel_empty": "No streams yet. Enter a stream URL above and click Add.",
            "panel_language": "Language",
            "panel_name_ph": "Name (optional)",
            "panel_show": "Show",
            "panel_fit": "Fit",
            "fit_contain": "Contain",
            "fit_cover": "Cover",
            "fit_fill": "Stretch",
            "panel_opacity": "Opacity",
            "panel_reload": "Reload",
            "panel_delete": "Delete",
            "lang_auto": "Auto",
        ],
        "ja": [
            "menu_open_panel": "管理画面を開く…",
            "menu_edit_mode": "配置モード",
            "menu_reload_all": "すべて再読み込み",
            "menu_quit": "終了",
            "edit_menu_title": "編集",
            "edit_undo": "取り消す",
            "edit_redo": "やり直す",
            "edit_cut": "カット",
            "edit_copy": "コピー",
            "edit_paste": "ペースト",
            "edit_select_all": "すべてを選択",
            "panel_arrange": "配置モード",
            "panel_arrange_on": "前面に出ています。ドラッグで移動・端でリサイズ・別ディスプレイへ移動できます。",
            "panel_arrange_off": "壁紙レイヤーに固定中（他アプリの後ろで再生）。",
            "panel_add": "追加",
            "panel_url_ph": "http://192.168.1.4:8081",
            "panel_empty": "ストリームがまだありません。上のURL欄にアドレスを入れて「追加」してください。",
            "panel_language": "言語",
            "panel_name_ph": "名前（任意）",
            "panel_show": "表示",
            "panel_fit": "表示方法",
            "fit_contain": "全体表示",
            "fit_cover": "切り抜き",
            "fit_fill": "引き伸ばし",
            "panel_opacity": "不透明度",
            "panel_reload": "再読み込み",
            "panel_delete": "削除",
            "lang_auto": "自動",
        ],
        "ko": [
            "menu_open_panel": "제어판 열기…",
            "menu_edit_mode": "배치 모드",
            "menu_reload_all": "모두 새로고침",
            "menu_quit": "종료",
            "edit_menu_title": "편집",
            "edit_undo": "실행 취소",
            "edit_redo": "다시 실행",
            "edit_cut": "오려두기",
            "edit_copy": "복사하기",
            "edit_paste": "붙여넣기",
            "edit_select_all": "전체 선택",
            "panel_arrange": "배치 모드",
            "panel_arrange_on": "창이 앞으로 나옵니다. 드래그로 이동, 가장자리로 크기 조절, 다른 디스플레이로 이동할 수 있습니다.",
            "panel_arrange_off": "배경화면 레이어에 고정됨(다른 앱 뒤에서 재생).",
            "panel_add": "추가",
            "panel_url_ph": "http://192.168.1.4:8081",
            "panel_empty": "스트림이 아직 없습니다. 위의 URL 칸에 주소를 입력하고 추가를 누르세요.",
            "panel_language": "언어",
            "panel_name_ph": "이름(선택 사항)",
            "panel_show": "표시",
            "panel_fit": "표시 방식",
            "fit_contain": "전체 보기",
            "fit_cover": "채우기",
            "fit_fill": "늘이기",
            "panel_opacity": "불투명도",
            "panel_reload": "새로고침",
            "panel_delete": "삭제",
            "lang_auto": "자동",
        ],
        "pt": [
            "menu_open_panel": "Abrir painel…",
            "menu_edit_mode": "Modo de organização",
            "menu_reload_all": "Recarregar tudo",
            "menu_quit": "Sair",
            "edit_menu_title": "Editar",
            "edit_undo": "Desfazer",
            "edit_redo": "Refazer",
            "edit_cut": "Recortar",
            "edit_copy": "Copiar",
            "edit_paste": "Colar",
            "edit_select_all": "Selecionar tudo",
            "panel_arrange": "Modo de organização",
            "panel_arrange_on": "As janelas estão à frente. Arraste para mover, arraste as bordas para redimensionar, mova entre telas.",
            "panel_arrange_off": "Fixado na camada do papel de parede (reproduzindo atrás dos outros apps).",
            "panel_add": "Adicionar",
            "panel_url_ph": "http://192.168.1.4:8081",
            "panel_empty": "Nenhum stream ainda. Digite a URL acima e clique em Adicionar.",
            "panel_language": "Idioma",
            "panel_name_ph": "Nome (opcional)",
            "panel_show": "Mostrar",
            "panel_fit": "Ajuste",
            "fit_contain": "Conter",
            "fit_cover": "Preencher",
            "fit_fill": "Esticar",
            "panel_opacity": "Opacidade",
            "panel_reload": "Recarregar",
            "panel_delete": "Excluir",
            "lang_auto": "Automático",
        ],
    ]
}
