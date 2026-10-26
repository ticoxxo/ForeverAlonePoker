import Foundation
import Security
import StoreKit

/// Pins StoreKit transactions to a bundled root certificate (tdr/0022).
/// StoreKit already verifies every transaction; this also checks that the
/// JWS chain (`x5c`) ends at the root this build expects and that its
/// ES256 signature matches the leaf. A transaction that fails is treated
/// like an unverified one: finished and never granted.
nonisolated struct TransactionCertificateValidator: Sendable {
    /// DER bytes of the pinned root. `nil` (the `.cer` is missing from the
    /// bundle) denies every transaction, so a forgotten file shows up in
    /// testing instead of granting skins unchecked.
    let rootCertificate: Data?
    /// Accept transactions from Xcode's local StoreKit testing on StoreKit's
    /// own verification. Their JWS carries a per-machine key that chains to
    /// no shippable root (the saved `StoreKitTestCertificate` only signs
    /// legacy receipts), so they cannot be pinned. Debug builds only.
    let trustsLocalTesting: Bool

    init(rootCertificate: Data?, trustsLocalTesting: Bool = false) {
        self.rootCertificate = rootCertificate
        self.trustsLocalTesting = trustsLocalTesting
    }

    /// Every App Store transaction (production, sandbox, TestFlight) chains
    /// to Apple Root CA - G3; Debug builds also trust Xcode's local testing.
    static func bundled(in bundle: Bundle = .main) -> TransactionCertificateValidator {
        // Holds Apple Root CA - G3: the root of StoreKit 2 JWS chains.
        let data = bundle.url(forResource: "AppleIncRootCertificate", withExtension: "cer").flatMap { try? Data(contentsOf: $0) }
        #if DEBUG
            return TransactionCertificateValidator(rootCertificate: data, trustsLocalTesting: true)
        #else
            return TransactionCertificateValidator(rootCertificate: data)
        #endif
    }

    /// `environment` is `Transaction.environment`, which StoreKit has already
    /// verified. Xcode transactions pass only when local testing is trusted;
    /// all others must chain to the pinned root.
    func validate(jws: String, environment: AppStore.Environment) -> Bool {
        if environment == .xcode { return trustsLocalTesting }
        return validate(jws: jws)
    }

    /// `jws` is `VerificationResult.jwsRepresentation`.
    func validate(jws: String) -> Bool {
        guard let rootCertificate,
              let root = SecCertificateCreateWithData(nil, rootCertificate as CFData) else { return false }
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Self.base64URLDecode(parts[0]),
              let payloadData = Self.base64URLDecode(parts[1]),
              let signature = Self.base64URLDecode(parts[2]),
              let header = try? JSONDecoder().decode(Header.self, from: headerData),
              header.alg == "ES256",
              let chain = header.x5c, !chain.isEmpty else { return false }

        let certificates = chain.compactMap { Data(base64Encoded: $0).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) } }
        guard certificates.count == chain.count,
              isTrusted(certificates, anchor: root, at: Self.signedDate(payloadData)),
              let leafKey = SecCertificateCopyKey(certificates[0]),
              let derSignature = Self.derSignature(fromRaw: signature) else { return false }

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        return SecKeyVerifySignature(leafKey, .ecdsaSignatureMessageX962SHA256, signingInput as CFData, derSignature as CFData, nil)
    }

    /// Only `root` is trusted: not the system store, and no network fetches.
    private func isTrusted(_ certificates: [SecCertificate], anchor root: SecCertificate, at date: Date?) -> Bool {
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else { return false }
        SecTrustSetAnchorCertificates(trust, [root] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetNetworkFetchAllowed(trust, false)
        // Judge the chain when the App Store signed it, as Apple's server
        // library does offline, so old transactions stay valid.
        if let date { SecTrustSetVerifyDate(trust, date as CFDate) }
        return SecTrustEvaluateWithError(trust, nil)
    }

    private struct Header: Decodable {
        let alg: String
        let x5c: [String]?
    }

    private struct Payload: Decodable {
        /// Milliseconds since 1970.
        let signedDate: Double?
    }

    private static func signedDate(_ payload: Data) -> Date? {
        guard let millis = (try? JSONDecoder().decode(Payload.self, from: payload))?.signedDate else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static func base64URLDecode(_ text: Substring) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    /// JWS carries r‖s (32 bytes each); Security wants an ASN.1 sequence.
    private static func derSignature(fromRaw raw: Data) -> Data? {
        guard raw.count == 64 else { return nil }
        func integer(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
            var value = Array(bytes.drop(while: { $0 == 0 }))
            if value.isEmpty { value = [0] }
            if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return [0x02, UInt8(value.count)] + value
        }
        let bytes = [UInt8](raw)
        let body = integer(bytes[0..<32]) + integer(bytes[32..<64])
        return Data([0x30, UInt8(body.count)] + body)
    }
}
