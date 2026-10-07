import CryptoKit
import Foundation
import Testing
@testable import ForeverAlonePoker

@Suite("LengthPrefixedFraming")
struct LengthPrefixedFramingTests {
    @Test("a frame is a big-endian length followed by the payload")
    func frame() {
        let framed = LengthPrefixedFraming.frame(Data("hello".utf8))
        #expect(Array(framed.prefix(4)) == [0, 0, 0, 5])
        #expect(framed.dropFirst(4) == Data("hello".utf8))
    }

    @Test("messages arriving split or coalesced are reassembled in order")
    func reassembly() throws {
        var decoder = LengthPrefixedFraming.Decoder()
        let a = LengthPrefixedFraming.frame(Data("first".utf8))
        let b = LengthPrefixedFraming.frame(Data("second".utf8))
        let stream = a + b

        // Split the two frames into odd chunks.
        let chunk1 = stream.prefix(3)
        let chunk2 = stream.dropFirst(3).prefix(10)
        let chunk3 = stream.dropFirst(13)

        #expect(try decoder.append(chunk1).isEmpty)
        #expect(try decoder.append(chunk2) == [Data("first".utf8)])
        #expect(try decoder.append(chunk3) == [Data("second".utf8)])
    }

    @Test("an empty payload is a valid frame")
    func emptyPayload() throws {
        var decoder = LengthPrefixedFraming.Decoder()
        #expect(try decoder.append(LengthPrefixedFraming.frame(Data())) == [Data()])
    }

    @Test("an absurd length is rejected instead of buffered forever")
    func tooLarge() {
        var decoder = LengthPrefixedFraming.Decoder()
        #expect(throws: LengthPrefixedFraming.FramingError.frameTooLarge(0x7FFF_FFFF)) {
            try decoder.append(Data([0x7F, 0xFF, 0xFF, 0xFF]))
        }
    }
}

@Suite("PasscodeKey")
struct PasscodeKeyTests {
    @Test("the same passcode derives the same key on both devices")
    func deterministic() {
        let a = PasscodeKey.derive(from: "1234")
        let b = PasscodeKey.derive(from: "1234")
        #expect(a.withUnsafeBytes { Data($0) } == b.withUnsafeBytes { Data($0) })
        #expect(a.bitCount == 256)
    }

    @Test("different passcodes derive different keys")
    func distinct() {
        let a = PasscodeKey.derive(from: "1234").withUnsafeBytes { Data($0) }
        let b = PasscodeKey.derive(from: "1235").withUnsafeBytes { Data($0) }
        #expect(a != b)
    }

    @Test("random passcodes are four digits")
    func format() {
        for _ in 0..<50 {
            let code = PasscodeKey.random()
            #expect(code.count == 4)
            #expect(code.allSatisfy { $0.isNumber })
        }
    }
}
