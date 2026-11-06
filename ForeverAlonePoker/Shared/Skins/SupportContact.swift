import Foundation

/// Where players reach us about purchases and the app (tdr/0022). The mail
/// carries only the app and OS versions; anything else is what they type.
nonisolated enum SupportContact {
    static let email = "jalmeidatorres18@gmail.com"
    /// Served by the game server (tdr/0035); the same URL goes in App Store Connect.
    static let privacyPolicy = URL(string: "https://forever-alone-poker.fly.dev/privacy")!

    /// Apple's own page on requesting refunds. We link to it instead of
    /// describing Apple's refund policy (HIG, Apple In-App Purchase).
    static let appleRefundHelp = URL(string: "https://support.apple.com/en-us/HT204084")!
    /// Where players follow up on a refund request they submitted.
    static let reportAProblem = URL(string: "https://reportaproblem.apple.com")!

    enum Topic: Sendable {
        case feedback
        case support
        /// A player reported from their seat (tdr/0029).
        case report(playerID: String, name: String, roomCode: String?)

        var subject: String {
            switch self {
            case .feedback: "ForeverAlonePoker feedback"
            case .support: "ForeverAlonePoker support"
            case .report(_, let name, _): "ForeverAlonePoker report: \(name)"
            }
        }

        /// What we need to find the player; the reporter adds what happened.
        var details: String {
            guard case .report(let playerID, let name, let roomCode) = self else { return "" }
            return "\n\n--\nReported player: \(name) (\(playerID))" + (roomCode.map { "\nRoom: \($0)" } ?? "")
        }
    }

    static func mailURL(
        _ topic: Topic,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
        system: String = "iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
    ) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: topic.subject),
            URLQueryItem(name: "body", value: "\(topic.details)\n\n--\nApp \(appVersion), \(system)"),
        ]
        return components.url!
    }
}
