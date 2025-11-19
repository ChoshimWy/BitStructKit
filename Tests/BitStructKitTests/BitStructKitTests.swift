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
    // 按你原始 C 结构声明字段类型（使用合适宽度）
    // 注意：字段类型使用 FixedWidthInteger 子类型（UInt8/UInt16/UInt64 等）
    // 字段顺序按 bit 流顺序声明（第一个字段是 byte[0] 的高位到低位）
    // 你的 C 定义是：
    // byte0: check_sum (8)
    // bytes1..7: reserve(55) + type(1)
    // byte8: mode(8)
    // byte9: command_type(7) + opera_type(1)
    var checkSum: UInt8 = 0
    var reserve: UInt64 = 0 // 55 bits 低位使用
    var type: UInt8 = 0 // 1 bit
    var mode: UInt8 = 0 // 8 bits
    var commandType: UInt8 = 0 // 7 bits
    var operaType: UInt8 = 0 // 1 bit

    static var fieldDescriptors: [AnyFieldDescriptor<DataPacket>] {
        return [
            AnyFieldDescriptor(keyPath: \.checkSum, size: 8),
            AnyFieldDescriptor(keyPath: \.reserve, size: 55),
            AnyFieldDescriptor(keyPath: \.type, size: 1),
            AnyFieldDescriptor(keyPath: \.mode, size: 8),
            AnyFieldDescriptor(keyPath: \.commandType, size: 7),
            AnyFieldDescriptor(keyPath: \.operaType, size: 1)
        ]
    }
}

// MARK: - FixtureError

enum FixtureError: Error {
    case invalidHexFixture
    case decodeFailed
}

@Test("验证数据一致性")
func bitStructVerifyDataConsistency() async throws {
    let hexPayload = "8d00000000000000018c"
    guard let payload = Data(hexString: hexPayload) else {
        throw FixtureError.invalidHexFixture
    }

    guard let decoded = DataPacket.decode(from: payload) else {
        throw FixtureError.decodeFailed
    }

    #expect(decoded.checkSum == 0x8D)
    #expect(decoded.reserve == 0)
    #expect(decoded.type == 0)
    #expect(decoded.mode == 0x01)
    #expect(decoded.commandType == 0x0C)
    #expect(decoded.operaType == 0x01)

    #expect(decoded.encode() == payload)

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
