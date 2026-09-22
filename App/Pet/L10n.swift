import Foundation

/// UI language: Korean when the system prefers it, English otherwise.
enum L10n {
    /// Test hook. Production code never sets this.
    nonisolated(unsafe) static var forceKorean: Bool? = nil

    static var isKorean: Bool {
        if let forceKorean { return forceKorean }
        return Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
    }

    static func text(_ ko: String, _ en: String) -> String {
        isKorean ? ko : en
    }
}
