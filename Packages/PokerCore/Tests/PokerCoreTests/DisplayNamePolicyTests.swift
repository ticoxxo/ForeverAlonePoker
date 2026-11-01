import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("DisplayNamePolicy")
struct DisplayNamePolicyTests {
    @Test("an ordinary name is accepted as typed")
    func ordinary() {
        #expect(DisplayNamePolicy.evaluate("Alice") == .accepted("Alice"))
    }

    @Test("accented and non-Latin names are accepted")
    func international() {
        #expect(DisplayNamePolicy.evaluate("José Ñúñez") == .accepted("José Ñúñez"))
        #expect(DisplayNamePolicy.evaluate("さくら") == .accepted("さくら"))
    }

    @Test("surrounding and repeated whitespace is collapsed")
    func whitespace() {
        #expect(DisplayNamePolicy.evaluate("  Big \n\t Slick  ") == .accepted("Big Slick"))
    }

    @Test("invisible and direction-override characters are removed")
    func invisible() {
        #expect(DisplayNamePolicy.evaluate("Al\u{200B}ice\u{202E}") == .accepted("Alice"))
    }

    @Test("an empty name is rejected")
    func empty() {
        #expect(DisplayNamePolicy.evaluate(" \u{200B} ") == .rejected(.empty))
    }

    @Test("a one-character name is too short")
    func tooShort() {
        #expect(DisplayNamePolicy.evaluate("A") == .rejected(.tooShort))
    }

    @Test("a name over the maximum length is too long")
    func tooLong() {
        let name = String(repeating: "a", count: DisplayNamePolicy.maxLength + 1)
        #expect(DisplayNamePolicy.evaluate(name) == .rejected(.tooLong))
    }

    @Test("a name with no letters or digits is rejected")
    func noLetters() {
        #expect(DisplayNamePolicy.evaluate("!!!") == .rejected(.invalidCharacters))
    }

    @Test("a blocked word is rejected whatever its case")
    func blockedWord() {
        #expect(DisplayNamePolicy.evaluate("Shit Happens") == .rejected(.blocked))
    }

    @Test("leetspeak, accents, fullwidth and stretched letters do not hide a blocked word")
    func disguised() {
        #expect(DisplayNamePolicy.evaluate("sh1t") == .rejected(.blocked))
        #expect(DisplayNamePolicy.evaluate("FUUUCK") == .rejected(.blocked))
        #expect(DisplayNamePolicy.evaluate("ｆｕｃｋ") == .rejected(.blocked))
        #expect(DisplayNamePolicy.evaluate("pütá") == .rejected(.blocked))
    }

    @Test("a blocked root hidden inside a longer word is rejected")
    func blockedRoot() {
        #expect(DisplayNamePolicy.evaluate("xXfuckerXx") == .rejected(.blocked))
    }

    @Test("ordinary words that contain a whole-word entry are accepted")
    func scunthorpe() {
        #expect(DisplayNamePolicy.evaluate("Scunthorpe") == .accepted("Scunthorpe"))
        #expect(DisplayNamePolicy.evaluate("Grapefruit") == .accepted("Grapefruit"))
        #expect(DisplayNamePolicy.evaluate("Computadora") == .accepted("Computadora"))
    }

    @Test("links are rejected")
    func links() {
        #expect(DisplayNamePolicy.evaluate("www.spam.example") == .rejected(.blocked))
    }

    @Test("the fallback name numbers seats from one")
    func fallback() {
        #expect(DisplayNamePolicy.fallbackName(for: .two) == "Player 2")
    }
}
