import Foundation
import PokerCore

nonisolated enum WireError: Error, Equatable {
    case versionMismatch(received: Int, expected: Int)
    case malformed
}

/// JSON encoding of protocol messages inside a versioned `Envelope`. Plain
/// `JSONEncoder` defaults are used on purpose so the server can decode the
/// same bytes with its own encoder configuration.
nonisolated enum WireCodec {
    static func encode<Message: Codable & Sendable & Hashable>(_ message: Message) throws -> Data {
        try JSONEncoder().encode(Envelope(message))
    }

    static func decode<Message: Codable & Sendable & Hashable>(_ type: Message.Type, from data: Data) throws -> Message {
        let envelope: Envelope<Message>
        do {
            envelope = try JSONDecoder().decode(Envelope<Message>.self, from: data)
        } catch {
            // A version bump usually changes the shape too, so try to surface
            // the version even when the payload no longer decodes.
            if let header = try? JSONDecoder().decode(VersionHeader.self, from: data),
               header.version != ProtocolVersion.current {
                throw WireError.versionMismatch(received: header.version, expected: ProtocolVersion.current)
            }
            throw WireError.malformed
        }
        guard envelope.version == ProtocolVersion.current else {
            throw WireError.versionMismatch(received: envelope.version, expected: ProtocolVersion.current)
        }
        return envelope.message
    }

    // MARK: - Text frames (WebSockets)

    static func encodeText<Message: Codable & Sendable & Hashable>(_ message: Message) throws -> String {
        String(decoding: try encode(message), as: UTF8.self)
    }

    static func decodeText<Message: Codable & Sendable & Hashable>(_ type: Message.Type, from text: String) throws -> Message {
        try decode(type, from: Data(text.utf8))
    }

    private struct VersionHeader: Decodable {
        let version: Int
    }
}
