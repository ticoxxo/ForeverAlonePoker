import Hummingbird
import HummingbirdTesting
import Testing
@testable import PokerServerCore

@Suite("Support page route")
struct SupportPageRouteTests {
    @Test("the support page is served as HTML with the support email")
    func served() async throws {
        let app = buildApplication()
        try await app.test(.router) { client in
            try await client.execute(uri: "/support", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType]?.hasPrefix("text/html") == true)
                let html = String(buffer: response.body)
                #expect(html.contains("mailto:\(PrivacyPolicy.contactEmail)"))
            }
        }
    }
}
