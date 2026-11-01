import Foundation
import Observation
import PokerCore

/// Checks the name this player wants others to see before it is saved
/// (tdr/0029), against CORE's policy. Every table checks it again when the
/// player sits down.
@Observable
final class ProfileSafetyModel {
    private(set) var nameError: String?
    private let identity: IdentityStore

    init(identity: IdentityStore) {
        self.identity = identity
    }

    /// Saves the name when it passes; returns it normalized, or `nil` and
    /// sets `nameError`.
    @discardableResult
    func commitName(_ raw: String) -> String? {
        switch DisplayNamePolicy.evaluate(raw) {
        case .rejected(let reason):
            nameError = Self.describe(reason)
            return nil
        case .accepted(let name):
            nameError = nil
            if name != identity.profile.displayName {
                identity.updateDisplayName(name)
            }
            return name
        }
    }

    static func describe(_ reason: DisplayNamePolicy.Reason) -> String {
        switch reason {
        case .empty: String(localized: "Enter a name.")
        case .tooShort: String(localized: "Use at least \(DisplayNamePolicy.minLength) characters.")
        case .tooLong: String(localized: "Use at most \(DisplayNamePolicy.maxLength) characters.")
        case .invalidCharacters: String(localized: "Use letters or numbers.")
        case .blocked: String(localized: "That name isn't allowed. Choose another one.")
        }
    }
}
