/// The rule every display name passes before anyone else sees it (tdr/0029).
/// The authority applies it on `join`, the app before saving, and the server
/// before its remote text check. It is a floor, not the whole filter: the
/// server adds a moderation API, and players can report and block.
///
/// Standard library only, so CORE stays free of Foundation: no NFKC, so the
/// common disguises (case, fullwidth forms, Latin accents, leetspeak,
/// stretched letters) are folded by hand.
public enum DisplayNamePolicy {
    public static let minLength = 2
    public static let maxLength = 20

    public enum Reason: String, Codable, Sendable, Hashable {
        case empty, tooShort, tooLong, invalidCharacters, blocked
    }

    public enum Verdict: Sendable, Hashable {
        /// The name to show, normalized.
        case accepted(String)
        case rejected(Reason)

        public var name: String? {
            if case .accepted(let name) = self { return name }
            return nil
        }
    }

    public static func evaluate(_ raw: String) -> Verdict {
        let name = normalize(raw)
        if name.isEmpty { return .rejected(.empty) }
        if name.count < minLength { return .rejected(.tooShort) }
        if name.count > maxLength { return .rejected(.tooLong) }
        guard name.unicodeScalars.contains(where: { $0.properties.isAlphabetic || $0.properties.numericType != nil }) else {
            return .rejected(.invalidCharacters)
        }
        if isBlocked(name) { return .rejected(.blocked) }
        return .accepted(name)
    }

    /// What a seat is called when its player's name is rejected.
    public static func fallbackName(for seat: Seat) -> String {
        "Player \(seat.rawValue + 1)"
    }

    /// The name as `evaluate` would accept it, or the seat's fallback.
    public static func displayName(_ raw: String, at seat: Seat) -> String {
        evaluate(raw).name ?? fallbackName(for: seat)
    }

    /// Two ASCII letters (ISO 3166-1 alpha-2), or empty.
    public static func countryCode(_ raw: String) -> String {
        let scalars = raw.unicodeScalars
        guard scalars.count == 2, scalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return "" }
        return raw
    }

    // MARK: - Normalizing

    /// Drops invisible and direction-changing characters, turns any
    /// whitespace into one space, and trims.
    public static func normalize(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control where !scalar.properties.isWhitespace, .format, .privateUse, .surrogate, .unassigned:
                continue
            default:
                break
            }
            if scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    // MARK: - Blocklist

    static func isBlocked(_ name: String) -> Bool {
        let folded = fold(name)
        let compact = runs(of: folded.filter { $0 != " " })
        if Blocklist.roots.contains(where: { compact.contains(runs(of: $0)) }) { return true }
        let tokens = folded.split(separator: " ").map { runs(of: String($0)) }
        return Blocklist.words.contains { word in
            let needle = runs(of: word)
            return tokens.contains { $0.matchesWhole(needle) }
        }
    }

    /// Lowercase ASCII letters and spaces: fullwidth forms to ASCII, Latin
    /// accents stripped, leetspeak read as letters, anything else a space.
    static func fold(_ name: String) -> String {
        var out = ""
        for scalar in name.lowercased().unicodeScalars {
            var value = scalar.value
            if (0xFF01...0xFF5E).contains(value) { value -= 0xFEE0 } // fullwidth ASCII
            guard let ascii = Unicode.Scalar(value) else { continue }
            let character = Character(ascii).lowercased().first ?? " "
            if let letter = lookalikes[character] {
                out.append(letter)
            } else if ("a"..."z").contains(character) {
                out.append(character)
            } else {
                out.append(" ")
            }
        }
        return out
    }

    private static let lookalikes: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
        "@": "a", "$": "s", "!": "i", "|": "i", "€": "e",
        "á": "a", "à": "a", "ä": "a", "â": "a", "ã": "a", "å": "a",
        "é": "e", "è": "e", "ë": "e", "ê": "e",
        "í": "i", "ì": "i", "ï": "i", "î": "i",
        "ó": "o", "ò": "o", "ö": "o", "ô": "o", "õ": "o",
        "ú": "u", "ù": "u", "ü": "u", "û": "u",
        "ñ": "n", "ç": "c", "ý": "y", "ÿ": "y",
    ]

    /// Letters with their repeat counts, so "fuuuck" still contains "fuck"
    /// while "niger" does not contain "nigger".
    static func runs(of text: String) -> Runs {
        var result: [Run] = []
        for character in text {
            if let last = result.last, last.letter == character {
                result[result.count - 1].count += 1
            } else {
                result.append(Run(letter: character, count: 1))
            }
        }
        return Runs(items: result)
    }

    struct Run: Hashable {
        let letter: Character
        var count: Int
    }

    struct Runs {
        let items: [Run]

        /// Whether `needle` appears with each letter repeated at least as often.
        func contains(_ needle: Runs) -> Bool {
            guard !needle.items.isEmpty, needle.items.count <= items.count else { return false }
            for start in 0...(items.count - needle.items.count) where matches(needle, at: start) {
                return true
            }
            return false
        }

        func matchesWhole(_ needle: Runs) -> Bool {
            needle.items.count == items.count && matches(needle, at: 0)
        }

        private func matches(_ needle: Runs, at start: Int) -> Bool {
            for (offset, run) in needle.items.enumerated() {
                let candidate = items[start + offset]
                guard candidate.letter == run.letter, candidate.count >= run.count else { return false }
            }
            return true
        }
    }
}

/// A deliberately short starter list in the languages the app ships first.
/// `roots` match anywhere in the name and must not occur inside everyday
/// words; `words` match a whole word only (the Scunthorpe problem).
enum Blocklist {
    static let roots: [String] = [
        // English
        "fuck", "nigger", "nigga", "faggot", "motherf", "asshole", "bitch",
        "pedophil", "paedophil", "hitler", "heilh",
        // Spanish
        "pendejo", "maricon", "culero", "chingad", "mierda", "hijodeput", "puton",
        // Spam
        "http", "www",
    ]

    static let words: [String] = [
        // English
        "shit", "cunt", "dick", "cock", "pussy", "whore", "slut", "rape", "rapist",
        "pedo", "nazi", "kike", "spic", "chink", "retard", "tranny", "porn", "sex",
        "anal", "penis", "vagina", "cum", "fag", "kkk",
        // Spanish
        "puta", "puto", "verga", "joto", "pinche", "culo", "zorra", "cabron", "polla",
        "cono", "pito",
    ]
}
