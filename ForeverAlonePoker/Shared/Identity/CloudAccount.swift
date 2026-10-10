import CloudKit
import Foundation

/// Whether the device is signed into iCloud for our container. Only ask when
/// the store is cloud-backed: `CKContainer` traps without the entitlement.
enum CloudAccount {
    static func isAvailable(containerID: String = Persistence.cloudContainerID) async -> Bool {
        let status = try? await CKContainer(identifier: containerID).accountStatus()
        return status == .available
    }
}
