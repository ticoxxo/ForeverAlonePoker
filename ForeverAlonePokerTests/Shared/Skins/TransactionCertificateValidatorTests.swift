import Foundation
import StoreKit
import Testing
@testable import ForeverAlonePoker

@Suite("TransactionCertificateValidator")
struct TransactionCertificateValidatorTests {
    private let root = TestCertificateAuthority()

    @Test("a transaction signed under the pinned root is accepted")
    func pinnedRoot() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate)
        #expect(validator.validate(jws: root.jws()))
    }

    @Test("a transaction signed under another root is denied")
    func otherRoot() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate)
        #expect(!validator.validate(jws: TestCertificateAuthority(commonName: "Impostor").jws()))
    }

    @Test("a payload changed after signing is denied")
    func tamperedPayload() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate)
        var parts = root.jws().split(separator: ".").map(String.init)
        parts[1] = TestCertificateAuthority.base64URL(Data(#"{"productId":"fap.skin.spanish_001.set"}"#.utf8))
        #expect(!validator.validate(jws: parts.joined(separator: ".")))
    }

    @Test("a transaction without a certificate chain is denied")
    func missingChain() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate)
        #expect(!validator.validate(jws: root.jws(includeChain: false)))
    }

    @Test("with no bundled certificate every transaction is denied")
    func noCertificate() {
        let validator = TransactionCertificateValidator(rootCertificate: nil)
        #expect(!validator.validate(jws: root.jws()))
    }

    @Test("garbage is denied")
    func garbage() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate)
        #expect(!validator.validate(jws: "not.a.jws"))
        #expect(!validator.validate(jws: ""))
    }

    @Test("an Xcode-signed transaction is accepted when local testing is trusted")
    func xcodeTrusted() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate, trustsLocalTesting: true)
        #expect(validator.validate(jws: TestCertificateAuthority(commonName: "Xcode").jws(), environment: .xcode))
    }

    @Test("an Xcode-signed transaction is denied when local testing is not trusted")
    func xcodeUntrusted() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate)
        #expect(!validator.validate(jws: root.jws(), environment: .xcode))
    }

    @Test("App Store transactions stay pinned while local testing is trusted")
    func appStoreStillPinned() {
        let validator = TransactionCertificateValidator(rootCertificate: root.certificate, trustsLocalTesting: true)
        #expect(validator.validate(jws: root.jws(), environment: .sandbox))
        #expect(!validator.validate(jws: TestCertificateAuthority(commonName: "Impostor").jws(), environment: .sandbox))
        #expect(!validator.validate(jws: TestCertificateAuthority(commonName: "Impostor").jws(), environment: .production))
    }
}
