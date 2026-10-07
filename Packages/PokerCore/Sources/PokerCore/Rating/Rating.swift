/// A player's competitive rating and how many ranked matches produced it.
public struct Rating: Codable, Sendable, Hashable, Comparable {
    public var value: Int
    public var matchesPlayed: Int

    public init(value: Int, matchesPlayed: Int = 0) {
        self.value = value
        self.matchesPlayed = matchesPlayed
    }

    /// Where every new ranked player starts.
    public static let initial = Rating(value: 1200, matchesPlayed: 0)

    public static func < (lhs: Rating, rhs: Rating) -> Bool {
        lhs.value < rhs.value
    }
}

/// Outcome of a ranked match from one player's side.
public enum MatchOutcome: Sendable, Hashable {
    case win
    case loss
    case draw

    /// Standard Elo score: 1 for a win, 0 for a loss, 0.5 for a draw.
    public var score: Double {
        switch self {
        case .win: 1
        case .loss: 0
        case .draw: 0.5
        }
    }
}

/// Elo rating updates. Runs on the server after every ranked online match
/// (tdr/0006) and on the client to preview changes; both must agree, which
/// is why the arithmetic lives here and is deterministic.
public enum EloCalculator {
    /// K-factor while a player is still "provisional"; large so the first
    /// matches move the rating quickly toward its true level.
    public static let provisionalK = 40
    public static let establishedK = 24
    /// Matches before a player stops being provisional.
    public static let provisionalMatches = 10

    public static func kFactor(for rating: Rating) -> Int {
        rating.matchesPlayed < provisionalMatches ? provisionalK : establishedK
    }

    /// Probability (0...1) that a player rated `rating` beats one rated `opponent`.
    public static func expectedScore(rating: Int, opponent: Int) -> Double {
        1 / (1 + pow10(Double(opponent - rating) / 400))
    }

    /// New ratings for both players after one match.
    public static func update(
        player: Rating,
        opponent: Rating,
        outcome: MatchOutcome
    ) -> (player: Rating, opponent: Rating) {
        let expected = expectedScore(rating: player.value, opponent: opponent.value)
        let playerDelta = round(Double(kFactor(for: player)) * (outcome.score - expected))
        let opponentDelta = round(Double(kFactor(for: opponent)) * ((1 - outcome.score) - (1 - expected)))
        return (
            Rating(value: player.value + Int(playerDelta), matchesPlayed: player.matchesPlayed + 1),
            Rating(value: opponent.value + Int(opponentDelta), matchesPlayed: opponent.matchesPlayed + 1)
        )
    }

    // MARK: - Math without Foundation

    /// 10^x for real x. CORE deliberately imports nothing beyond the standard
    /// library, which has no `pow`, so this uses exp(x·ln 10) with a short
    /// series after range reduction. Accurate to far better than one rating point.
    static func pow10(_ x: Double) -> Double {
        exp(x * 2.302585092994046)
    }

    static func exp(_ x: Double) -> Double {
        // Range-reduce so the series converges fast, then square back up.
        var halvings = 0
        var reduced = x
        while reduced.magnitude > 0.5 {
            reduced /= 2
            halvings += 1
        }
        var term = 1.0
        var sum = 1.0
        for n in 1...12 {
            term *= reduced / Double(n)
            sum += term
        }
        for _ in 0..<halvings {
            sum *= sum
        }
        return sum
    }

    static func round(_ x: Double) -> Double {
        x.rounded(.toNearestOrAwayFromZero)
    }
}
