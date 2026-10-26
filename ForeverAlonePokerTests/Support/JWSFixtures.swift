import Foundation
import Security

/// A self-signed P-256 certificate made at test time, standing in for the
/// StoreKit test root or Apple Root CA - G3, and JWS strings signed with it
/// the way the App Store (or Xcode's StoreKit testing) signs transactions.
struct TestCertificateAuthority {
    let privateKey: SecKey
    /// DER bytes of the self-signed certificate.
    let certificate: Data

    init(commonName: String = "Test StoreKit Root") {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
        let publicKey = SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(privateKey)!, nil)! as Data
        certificate = Self.selfSigned(commonName: commonName, publicKey: publicKey, signer: privateKey)
    }

    /// A compact JWS with this certificate as the whole `x5c` chain.
    func jws(payload: [String: Any] = TestCertificateAuthority.payload(), includeChain: Bool = true) -> String {
        var header: [String: Any] = ["alg": "ES256"]
        if includeChain { header["x5c"] = [certificate.base64EncodedString()] }
        let signingInput = Self.base64URL(json(header)) + "." + Self.base64URL(json(payload))
        let der = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, Data(signingInput.utf8) as CFData, nil)! as Data
        return signingInput + "." + Self.base64URL(Self.rawSignature(fromDER: der))
    }

    static func payload(productID: String = "fap.skin.red_check", signedAt date: Date = .now) -> [String: Any] {
        ["productId": productID, "signedDate": Int(date.timeIntervalSince1970 * 1000)]
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// JWS carries ES256 signatures as raw r‖s, 32 bytes each.
    private static func rawSignature(fromDER der: Data) -> Data {
        let bytes = [UInt8](der)
        var index = 2  // SEQUENCE tag and short length
        func integer() -> [UInt8] {
            let length = Int(bytes[index + 1])
            var value = Array(bytes[(index + 2)..<(index + 2 + length)])
            index += 2 + length
            while value.count > 32, value.first == 0 { value.removeFirst() }
            return Array(repeating: 0, count: 32 - value.count) + value
        }
        return Data(integer() + integer())
    }

    // MARK: - Minimal DER for an X.509 v3 certificate

    private static func selfSigned(commonName: String, publicKey: Data, signer: SecKey) -> Data {
        let ecdsaWithSHA256 = sequence(oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
        let name = sequence(set(sequence(oid([0x55, 0x04, 0x03]) + tlv(0x0C, Array(commonName.utf8)))))
        let validity = sequence(utcTime(.now.addingTimeInterval(-86_400)) + utcTime(.now.addingTimeInterval(86_400 * 365)))
        let keyInfo = sequence(
            sequence(oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]) + oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]))
                + tlv(0x03, [0x00] + Array(publicKey))
        )
        // basicConstraints, critical, CA:TRUE
        let basicConstraints = sequence(oid([0x55, 0x1D, 0x13]) + tlv(0x01, [0xFF]) + tlv(0x04, sequence(tlv(0x01, [0xFF]))))
        let extensions = tlv(0xA3, sequence(basicConstraints))
        let tbs = sequence(
            tlv(0xA0, tlv(0x02, [0x02]))           // version v3
                + tlv(0x02, [0x01])                // serial number
                + ecdsaWithSHA256 + name + validity + name + keyInfo + extensions
        )
        let signature = SecKeyCreateSignature(signer, .ecdsaSignatureMessageX962SHA256, Data(tbs) as CFData, nil)! as Data
        return Data(sequence(tbs + ecdsaWithSHA256 + tlv(0x03, [0x00] + Array(signature))))
    }

    private static func tlv(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        var length: [UInt8]
        if value.count < 0x80 {
            length = [UInt8(value.count)]
        } else {
            var count = value.count
            length = []
            while count > 0 { length.insert(UInt8(count & 0xFF), at: 0); count >>= 8 }
            length.insert(0x80 | UInt8(length.count), at: 0)
        }
        return [tag] + length + value
    }

    private static func sequence(_ content: [UInt8]) -> [UInt8] { tlv(0x30, content) }
    private static func set(_ content: [UInt8]) -> [UInt8] { tlv(0x31, content) }
    private static func oid(_ encoded: [UInt8]) -> [UInt8] { tlv(0x06, encoded) }

    private static func utcTime(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Array(formatter.string(from: date).utf8))
    }
}
