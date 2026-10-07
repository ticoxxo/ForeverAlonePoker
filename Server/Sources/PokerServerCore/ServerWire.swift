import Foundation
import PokerCore

public enum ServerWireError: Error, Equatable {
    case versionMismatch(received: Int, expected: Int)
    case malformed
}

/// JSON envelope codec, byte-compatible with the app's `WireCodec`.
public enum ServerWire {
    public static func encode<Message: Codable & Sendable & Hashable>(_ message: Message) throws -> String {
        let data = try JSONEncoder().encode(Envelope(message))
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode<Message: Codable & Sendable & Hashable>(_ type: Message.Type, from text: String) throws -> Message {
        let data = Data(text.utf8)
        let envelope: Envelope<Message>
        do {
            envelope = try JSONDecoder().decode(Envelope<Message>.self, from: data)
        } catch {
            if let header = try? JSONDecoder().decode(VersionHeader.self, from: data),
               header.version != ProtocolVersion.current {
                throw ServerWireError.versionMismatch(received: header.version, expected: ProtocolVersion.current)
            }
            throw ServerWireError.malformed
        }
        guard envelope.version == ProtocolVersion.current else {
            throw ServerWireError.versionMismatch(received: envelope.version, expected: ProtocolVersion.current)
        }
        return envelope.message
    }

    private struct VersionHeader: Decodable {
        let version: Int
    }
}
