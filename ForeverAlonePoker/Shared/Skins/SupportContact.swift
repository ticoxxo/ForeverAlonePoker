import Foundation

/// Where players reach us about purchases and the app (tdr/0022). The mail
/// carries only the app and OS versions; anything else is what they type.
nonisolated enum SupportContact {
    static let email = "jalmeidatorres18@gmail.com"

    /// Apple's own page on requesting refunds. We link to it instead of
    /// describing Apple's refund policy (HIG, Apple In-App Purchase).
    static let appleRefundHelp = URL(string: "https://support.apple.com/en-us/HT204084")!
    /// Where players follow up on a refund request they submitted.
    static let reportAProblem = URL(string: "https://reportaproblem.apple.com")!

    enum Topic: Sendable {
        case feedback
        case support

        var subject: String {
            switch self {
            case .feedback: "ForeverAlonePoker feedback"
            case .support: "ForeverAlonePoker support"
            }
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
            URLQueryItem(name: "body", value: "\n\n--\nApp \(appVersion), \(system)"),
        ]
        return components.url!
    }
}
