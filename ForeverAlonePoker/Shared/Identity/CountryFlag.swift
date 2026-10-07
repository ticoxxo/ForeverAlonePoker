import Foundation

/// Helpers for ISO 3166-1 alpha-2 region codes.
nonisolated enum CountryFlag {
    /// The flag emoji for a region code ("MX" → 🇲🇽), or an empty string for
    /// anything that is not two ASCII letters.
    static func emoji(for code: String) -> String {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ ("A"..."Z").contains(Character($0)) }) else { return "" }
        let base: UInt32 = 0x1F1E6 - 65
        return String(String.UnicodeScalarView(letters.compactMap { Unicode.Scalar(base + $0.value) }))
    }

    /// Localised region name, or the code itself when the locale has no name for it.
    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// All two-letter regions sorted by their localised name.
    static func allRegionCodes(locale: Locale = .current) -> [String] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 }
            .sorted { name(for: $0, locale: locale).localizedCaseInsensitiveCompare(name(for: $1, locale: locale)) == .orderedAscending }
    }
}
