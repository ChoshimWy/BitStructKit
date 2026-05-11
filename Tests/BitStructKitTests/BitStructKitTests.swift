import Foundation
import Testing
@testable import BitStructKit

// MARK: - DataPacket

// typedef struct{
//     uint8_t    check_sum:8;
//     uint64_t   reserve:55;
//     uint8_t    type:1;
//     uint8_t    mode:8;
//     uint8_t    command_type:7;
//     uint8_t    opera_type:1;
// } DataPacket;

struct DataPacket: BitStructCodable {
    // Mirror the original C struct using appropriately sized fixed-width integers.
    // Descriptor order follows the wire-order bit stream, where the first field occupies
    // the lowest available bit in byte 0.
    // Bytes are usually displayed as bit7 -> bit0, but the library allocates bits within
    // each byte in LSB-first order.
    // The C definition maps to:
    // byte0: check_sum (8)
    // bytes1..7: reserve(55) + type(1)
    // byte8: mode(8)
    // byte9: command_type(7, bits 6...0) + opera_type(1, bit 7)
    var checkSum: UInt8 = 0
    var reserve: UInt64 = 0 // Uses the low 55 bits.
    var type: UInt8 = 0 // 1 bit.
    var mode: UInt8 = 0 // 8 bits.
    var commandType: UInt8 = 0 // 7 bits.
    var operaType: UInt8 = 0 // 1 bit.

    static let fieldDescriptors: [AnyFieldDescriptor<DataPacket>] = [
            AnyFieldDescriptor(keyPath: \.checkSum, size: 8),
            AnyFieldDescriptor(keyPath: \.reserve, size: 55),
            AnyFieldDescriptor(keyPath: \.type, size: 1),
            AnyFieldDescriptor(keyPath: \.mode, size: 8),
            AnyFieldDescriptor(keyPath: \.commandType, size: 7),
            AnyFieldDescriptor(keyPath: \.operaType, size: 1)
    ]
}

// MARK: - FixtureError

enum FixtureError: Error {
    case invalidHexFixture
    case decodeFailed
}

@Test("Round-trips the documented packet payload")
func bitStructVerifyDataConsistency() async throws {
    let hexPayload = "8d00000000000000018c"
    guard let payload = Data(hexString: hexPayload) else {
        throw FixtureError.invalidHexFixture
    }

    guard let decoded = DataPacket.decodeIfPossible(from: payload) else {
        throw FixtureError.decodeFailed
    }

    #expect(decoded.checkSum == 0x8D)
    #expect(decoded.reserve == 0)
    #expect(decoded.type == 0)
    #expect(decoded.mode == 0x01)
    #expect(decoded.commandType == 0x0C)
    #expect(decoded.operaType == 0x01)

    #expect(decoded.encode() == payload)

    var reusedData = Data(repeating: 0xFF, count: payload.count)
    decoded.encode(into: &reusedData)
    #expect(reusedData == payload)

    var manualPacket = DataPacket()
    manualPacket.operaType = 0x01
    manualPacket.commandType = 0x0C
    manualPacket.mode = 1
    manualPacket.type = 0
    let sum = manualPacket.encode().dropFirst().reduce(UInt8(0)) { $0 &+ $1 }
    manualPacket.checkSum = sum
    let data = manualPacket.encode()
    let hex = data.hexString
    #expect(hex.lowercased() == hexPayload.lowercased())
}

@Test("Reports insufficient bytes for short input")
func bitStructDecodeThrowsOnShortData() async throws {
    let shortPayload = Data([0x00])

    #expect(DataPacket.decodeIfPossible(from: shortPayload) == nil)

    do {
        _ = try DataPacket.decode(from: shortPayload)
        #expect(Bool(false))
    } catch let error as BitStructDecodingError {
        #expect(error == .insufficientBytes(expected: 10, actual: 1))
    }
}

// MARK: - SignedPacket

struct SignedPacket: BitStructCodable {
    var signedNibble: Int8 = 0

    static let fieldDescriptors: [AnyFieldDescriptor<SignedPacket>] = [
        AnyFieldDescriptor(keyPath: \.signedNibble, size: 4)
    ]
}

@Test("Round-trips a signed bitfield")
func bitStructSignedFieldRoundTrip() async throws {
    var packet = SignedPacket()
    packet.signedNibble = -1

    let encoded = packet.encode()
    #expect(encoded == Data([0x0F]))

    guard let decoded = SignedPacket.decodeIfPossible(from: encoded) else {
        throw FixtureError.decodeFailed
    }
    #expect(decoded.signedNibble == -1)

    let negativeEight = SignedPacket.decodeIfPossible(from: Data([0x08]))
    #expect(negativeEight?.signedNibble == -8)

    var buffer = [UInt8]()
    packet.encode(into: &buffer)
    #expect(buffer == [0x0F])
}

// MARK: - MixedWidthPacket

struct MixedWidthPacket: BitStructCodable {
    var header: UInt8 = 0
    var payload: UInt16 = 0
    var trailer: UInt8 = 0

    static let fieldDescriptors: [AnyFieldDescriptor<MixedWidthPacket>] = [
            AnyFieldDescriptor(keyPath: \.header, size: 3),
            AnyFieldDescriptor(keyPath: \.payload, size: 10),
            AnyFieldDescriptor(keyPath: \.trailer, size: 5)
    ]
}

@Test("Encodes mixed-width fields across byte boundaries")
func bitStructEncodesAcrossByteBoundaries() async throws {
    var packet = MixedWidthPacket()
    packet.header = 0b101
    packet.payload = 0b10_1010_1010
    packet.trailer = 0b10101

    let encoded = packet.encode()
    #expect(encoded == Data([0x55, 0xB5, 0x02]))

    let decoded = try MixedWidthPacket.decodeExactly(from: encoded)
    #expect(decoded.header == packet.header)
    #expect(decoded.payload == packet.payload)
    #expect(decoded.trailer == packet.trailer)
}

// MARK: - MisreportedBitCountPacket

struct MisreportedBitCountPacket: BitStructCodable {
    static var totalBitCount: Int { 1 }

    var value: UInt16 = 0

    static let fieldDescriptors: [AnyFieldDescriptor<MisreportedBitCountPacket>] = [
        AnyFieldDescriptor(keyPath: \.value, size: 16)
    ]
}

@Test("Ignores custom totalBitCount overrides during encoding")
func bitStructIgnoresCustomTotalBitCountOverride() async throws {
    var packet = MisreportedBitCountPacket()
    packet.value = 0xABCD

    let layout = BitStructLayout.metadata(for: MisreportedBitCountPacket.self)
    #expect(layout.totalBitCount == 16)
    #expect(layout.totalByteCount == 2)
    #expect(layout.fieldDescriptors.map(\.size) == [16])

    let encoded = packet.encode()
    #expect(encoded == Data([0xCD, 0xAB]))

    let decoded = try MisreportedBitCountPacket.decodeExactly(from: encoded)
    #expect(decoded.value == 0xABCD)
}

@Test("Strict decode rejects trailing bytes")
func bitStructStrictDecodeRejectsTrailingBytes() async throws {
    let payload = Data([0x0F, 0x00])

    #expect(SignedPacket.decodeIfPossible(from: payload)?.signedNibble == -1)
    #expect(SignedPacket.decodeIfPossibleExactly(from: payload) == nil)

    do {
        _ = try SignedPacket.decodeExactly(from: payload)
        #expect(Bool(false))
    } catch let error as BitStructDecodingError {
        #expect(error == .trailingBytes(expected: 1, actual: 2))
    }
}

// MARK: - ZeroWidthPacket

struct ZeroWidthPacket: BitStructCodable {
    var flag: UInt8 = 0
    var ignored: UInt8 = 0
    var nibble: UInt8 = 0

    static let fieldDescriptors: [AnyFieldDescriptor<ZeroWidthPacket>] = [
        AnyFieldDescriptor(keyPath: \.flag, size: 1),
        AnyFieldDescriptor(keyPath: \.ignored, size: 0),
        AnyFieldDescriptor(keyPath: \.nibble, size: 3)
    ]
}

@Test("Zero-width fields do not consume layout bits")
func bitStructZeroWidthFieldDoesNotAffectLayout() async throws {
    var packet = ZeroWidthPacket()
    packet.flag = 1
    packet.ignored = 0xFF
    packet.nibble = 0b101

    let encoded = packet.encode()
    #expect(encoded == Data([0x0B]))
    let layout = BitStructLayout.metadata(for: ZeroWidthPacket.self)
    #expect(layout.totalBitCount == 4)
    #expect(layout.totalByteCount == 1)
    #expect(layout.fieldDescriptors.map(\.size) == [1, 0, 3])

    let decoded = try ZeroWidthPacket.decodeExactly(from: encoded)
    #expect(decoded.flag == 1)
    #expect(decoded.ignored == 0)
    #expect(decoded.nibble == 0b101)
}

@Test("Layout metadata exposes a read-only descriptor snapshot")
func bitStructLayoutMetadataExposesDescriptorSnapshot() async throws {
    let layout = BitStructLayout.metadata(for: DataPacket.self)

    #expect(layout.totalBitCount == 80)
    #expect(layout.totalByteCount == 10)
    #expect(layout.fieldDescriptors.map(\.size) == [8, 55, 1, 8, 7, 1])
}

// MARK: - FullWidth Packets

struct FullWidthUInt64Packet: BitStructCodable {
    var value: UInt64 = 0

    static let fieldDescriptors: [AnyFieldDescriptor<FullWidthUInt64Packet>] = [
        AnyFieldDescriptor(keyPath: \.value, size: 64)
    ]
}

struct FullWidthInt64Packet: BitStructCodable {
    var value: Int64 = 0

    static let fieldDescriptors: [AnyFieldDescriptor<FullWidthInt64Packet>] = [
        AnyFieldDescriptor(keyPath: \.value, size: 64)
    ]
}

@Test("Round-trips a full-width UInt64 field")
func bitStructFullWidthUInt64RoundTrip() async throws {
    var packet = FullWidthUInt64Packet()
    packet.value = 0x0123_4567_89AB_CDEF

    let encoded = packet.encode()
    #expect(encoded == Data([0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]))

    let decoded = try FullWidthUInt64Packet.decodeExactly(from: encoded)
    #expect(decoded.value == packet.value)
}

@Test("Round-trips a full-width Int64 field")
func bitStructFullWidthInt64RoundTrip() async throws {
    var packet = FullWidthInt64Packet()
    packet.value = -2

    let encoded = packet.encode()
    #expect(encoded == Data([0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))

    let decoded = try FullWidthInt64Packet.decodeExactly(from: encoded)
    #expect(decoded.value == packet.value)
}

extension Data {
    init?(hexString: String) {
        let cleanString = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanString.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleanString.count / 2)
        var index = cleanString.startIndex

        while index < cleanString.endIndex {
            let nextIndex = cleanString.index(index, offsetBy: 2)
            let byteString = cleanString[index ..< nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }

        self = data
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
