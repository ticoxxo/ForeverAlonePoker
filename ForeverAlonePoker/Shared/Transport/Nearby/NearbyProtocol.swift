import CryptoKit
import Foundation
import Network

/// Splits a TCP byte stream into discrete messages with a 4-byte big-endian
/// length prefix. Pure so it can be unit-tested without a socket.
nonisolated enum LengthPrefixedFraming {
    static let headerSize = 4
    /// Protects against a hostile or buggy peer announcing a gigantic frame.
    static let maxFrameSize = 1 << 20

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: headerSize)
        framed.append(payload)
        return framed
    }

    /// Accumulates bytes and hands back every complete message.
    struct Decoder: Sendable {
        private var buffer = Data()

        init() {}

        mutating func append(_ data: Data) throws -> [Data] {
            buffer.append(data)
            var frames: [Data] = []
            while buffer.count >= headerSize {
                // `Data` slices keep their parent's indices, so always offset
                // from `startIndex` rather than assuming it is zero.
                let start = buffer.startIndex
                let header = buffer[start..<(start + headerSize)]
                let length = Int(header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                guard length <= maxFrameSize else { throw FramingError.frameTooLarge(length) }
                guard buffer.count >= headerSize + length else { break }
                let payloadStart = start + headerSize
                frames.append(Data(buffer[payloadStart..<(payloadStart + length)]))
                buffer = Data(buffer[(payloadStart + length)...])
            }
            return frames
        }
    }

    enum FramingError: Error, Equatable {
        case frameTooLarge(Int)
    }
}

/// Turns the short passcode the host shows into the TLS pre-shared key both
/// devices use, so nobody on the Wi-Fi can read the cards in flight and a
/// stranger cannot join without the code.
nonisolated enum PasscodeKey {
    private static let salt = SymmetricKey(data: Data("ForeverAlonePoker.nearby.v1".utf8))

    static func derive(from passcode: String) -> SymmetricKey {
        let code = HMAC<SHA256>.authenticationCode(for: Data(passcode.utf8), using: salt)
        return SymmetricKey(data: Data(code))
    }

    /// Four digits, easy to read aloud across a table.
    static func random() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}

/// `NWParameters` for the nearby link: TCP with keepalive, TLS-PSK from the
/// passcode, and peer-to-peer Wi-Fi so no router is required.
nonisolated enum NearbyParameters {
    static let serviceType = "_fapoker._tcp"
    static let pskIdentity = "fapoker"

    static func make(passcode: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = PasscodeKey.derive(from: passcode)
        let psk = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, psk as dispatch_data_t, identity as dispatch_data_t)
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    /// Browsing needs no security; it only discovers names.
    static func browsing() -> NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }
}
