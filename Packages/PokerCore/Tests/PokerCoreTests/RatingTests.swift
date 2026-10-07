import Testing
@testable import PokerCore

@Suite("EloCalculator")
struct EloCalculatorTests {
    @Test("expected score is one half between equals and bounded by 0 and 1")
    func expectedScore() {
        #expect(EloCalculator.expectedScore(rating: 1200, opponent: 1200) == 0.5)
        let strong = EloCalculator.expectedScore(rating: 1600, opponent: 1200)
        let weak = EloCalculator.expectedScore(rating: 1200, opponent: 1600)
        #expect(strong > 0.9 && strong < 0.92, "400 points ≈ 10:1 odds, so ≈ 0.909")
        #expect(abs(strong + weak - 1) < 1e-9)
        #expect(EloCalculator.expectedScore(rating: 0, opponent: 4000) > 0)
        #expect(EloCalculator.expectedScore(rating: 4000, opponent: 0) < 1)
    }

    @Test("the standard-library exp and power helpers are accurate")
    func mathHelpers() {
        #expect(abs(EloCalculator.exp(0) - 1) < 1e-12)
        #expect(abs(EloCalculator.exp(1) - 2.718281828459045) < 1e-9)
        #expect(abs(EloCalculator.exp(-3) - 0.049787068367863944) < 1e-9)
        #expect(abs(EloCalculator.pow10(2) - 100) < 1e-6)
        #expect(abs(EloCalculator.pow10(-1) - 0.1) < 1e-9)
    }

    @Test("equal established players exchange half the K-factor")
    func equalEstablished() {
        let a = Rating(value: 1500, matchesPlayed: 50)
        let b = Rating(value: 1500, matchesPlayed: 50)
        let result = EloCalculator.update(player: a, opponent: b, outcome: .win)
        #expect(result.player.value == 1512)
        #expect(result.opponent.value == 1488)
        #expect(result.player.matchesPlayed == 51)
        #expect(result.opponent.matchesPlayed == 51)
    }

    @Test("provisional players move faster")
    func provisional() {
        let result = EloCalculator.update(player: .initial, opponent: .initial, outcome: .win)
        #expect(result.player.value == 1220)
        #expect(result.opponent.value == 1180)
        #expect(EloCalculator.kFactor(for: .initial) == EloCalculator.provisionalK)
        #expect(EloCalculator.kFactor(for: Rating(value: 1200, matchesPlayed: 10)) == EloCalculator.establishedK)
    }

    @Test("beating a much stronger player pays more than beating a weaker one")
    func upsetPaysMore() {
        let me = Rating(value: 1200, matchesPlayed: 20)
        let upset = EloCalculator.update(player: me, opponent: Rating(value: 1600, matchesPlayed: 20), outcome: .win)
        let routine = EloCalculator.update(player: me, opponent: Rating(value: 800, matchesPlayed: 20), outcome: .win)
        #expect(upset.player.value - me.value == 22)
        #expect(routine.player.value - me.value == 2)
    }

    @Test("a loss mirrors a win and a draw between equals changes nothing")
    func lossAndDraw() {
        let a = Rating(value: 1300, matchesPlayed: 20)
        let b = Rating(value: 1300, matchesPlayed: 20)
        let loss = EloCalculator.update(player: a, opponent: b, outcome: .loss)
        #expect(loss.player.value == 1288)
        #expect(loss.opponent.value == 1312)
        let draw = EloCalculator.update(player: a, opponent: b, outcome: .draw)
        #expect(draw.player.value == 1300)
        #expect(draw.opponent.value == 1300)
    }

    @Test("with equal K-factors rating points are conserved")
    func conservation() {
        let a = Rating(value: 1450, matchesPlayed: 30)
        let b = Rating(value: 1375, matchesPlayed: 30)
        let result = EloCalculator.update(player: a, opponent: b, outcome: .loss)
        #expect(result.player.value + result.opponent.value == a.value + b.value)
    }

    @Test("ratings compare by value")
    func comparable() {
        #expect(Rating(value: 1100) < Rating(value: 1200))
        #expect(Rating.initial.value == 1200)
    }
}
