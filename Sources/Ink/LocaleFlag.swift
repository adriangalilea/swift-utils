import Foundation

// A locale as a HUMAN reads it: the flag, never a code ("es" is
// engineering leaking into the interface). Region subtag when the BCP-47
// id carries one ("es-ES" -> 🇪🇸), a small language->home-region map when
// it does not.
public enum LocaleFlag {
    private static let homeRegion: [String: String] = [
        "en": "US", "es": "ES", "fr": "FR", "de": "DE", "it": "IT",
        "pt": "PT", "ja": "JP", "ko": "KR", "zh": "CN", "ru": "RU",
    ]

    public static func emoji(_ bcp47: String?) -> String? {
        guard let bcp47, !bcp47.isEmpty else { return nil }
        let parts = bcp47.split(separator: "-")
        var region = parts.dropFirst().first(where: { $0.count == 2 })
            .map { String($0).uppercased() }
        if region == nil, let language = parts.first {
            region = homeRegion[String(language).lowercased()]
        }
        guard let region, region.count == 2 else { return nil }
        return String(
            region.unicodeScalars.compactMap {
                Unicode.Scalar(0x1F1E6 + $0.value - Unicode.Scalar("A").value)
                    .map(Character.init)
            })
    }
}
