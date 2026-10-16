import Foundation
import Testing
@testable import ForeverAlonePoker

private struct StubAvatars: AvatarProviding {
    let pictures: [String: Data]
    var delay: Duration = .zero
    let calls = CallCounter()

    func avatars(for playerIDs: [String]) async throws -> [String: Data] {
        calls.increment()
        try await Task.sleep(for: delay)
        return pictures.filter { playerIDs.contains($0.key) }
    }
}

private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

@Suite("AvatarLoader")
@MainActor
struct AvatarLoaderTests {
    @Test("found pictures are cached and each player is asked for once")
    func caches() async {
        let stub = StubAvatars(pictures: ["ana": Data([1, 2, 3])])
        let loader = AvatarLoader(provider: stub)
        await loader.load(["ana", "bruno"])
        #expect(loader.avatar(for: "ana") == Data([1, 2, 3]))
        #expect(loader.avatar(for: "bruno") == nil, "no picture means initials")

        await loader.load(["ana", "bruno"])
        #expect(stub.calls.count == 1)
    }

    @Test("a slow lookup gives up after the timeout")
    func timeout() async {
        let stub = StubAvatars(pictures: ["ana": Data([1])], delay: .seconds(30))
        let loader = AvatarLoader(provider: stub, timeout: .milliseconds(50))
        await loader.load(["ana"])
        #expect(loader.avatar(for: "ana") == nil)
    }

    @Test("initials take the first letters of the first and last words")
    func initials() {
        #expect(AvatarView.initials(of: "Ana María López") == "AL")
        #expect(AvatarView.initials(of: "bob") == "B")
        #expect(AvatarView.initials(of: "  ") == "")
    }
}
