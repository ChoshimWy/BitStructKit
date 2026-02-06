//
//  BitStructKit.swift
//  BitStructKit
//
//  Created by Choshim.Wei on 2025/11/19.
//  Copyright © 2025 Choshim.Wei. All rights reserved.
//

import Foundation

// MARK: - BitStructCodable

public protocol BitStructCodable {
    // 用于 decode 时创建空实例
    init()
    static var totalBitCount: Int { get }
    static var fieldDescriptors: [AnyFieldDescriptor<Self>] { get }
}

public enum BitStructDecodingError: Error, Equatable {
    case insufficientBytes(expected: Int, actual: Int)
}

extension BitStructCodable {
    public static var totalBitCount: Int {
        fieldDescriptors.reduce(0) { $0 + $1.size }
    }

    private static func mask(for size: Int) -> UInt64 {
        if size >= 64 {
            return UInt64.max
        }
        if size <= 0 {
            return 0
        }
        return (1 << size) - 1
    }

    // MARK: - encode -> Data (little-endian bit packing like Clang bitfields)

    public func encode() -> Data {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8

        var buffer = [UInt8](repeating: 0, count: totalBytes)
        encode(into: &buffer)
        return Data(buffer)
    }

    public func encode(into data: inout Data) {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8

        var buffer = [UInt8](repeating: 0, count: totalBytes)
        encode(into: &buffer)
        data = Data(buffer)
    }

    public func encode(into buffer: inout [UInt8]) {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8

        if buffer.count != totalBytes {
            buffer = [UInt8](repeating: 0, count: totalBytes)
        } else {
            buffer.withUnsafeMutableBufferPointer { rawBuffer in
                rawBuffer.initialize(repeating: 0)
            }
        }

        var bitOffset = 0 // 已写入位数，从 LSB -> MSB

        for field in Self.fieldDescriptors {
            if field.size == 0 {
                continue
            }

            let raw = field.getter(self) & Self.mask(for: field.size)

            if bitOffset % 8 == 0 && field.size % 8 == 0 {
                let byteIndex = bitOffset / 8
                let byteCount = field.size / 8
                for byteOffset in 0 ..< byteCount {
                    buffer[byteIndex + byteOffset] = UInt8((raw >> UInt64(8 * byteOffset)) & 0xFF)
                }
                bitOffset += field.size
                continue
            }

            // 将 field.size 位从 raw 的低位写入 buffer 从 bitOffset 开始（little-endian bit ordering）
            for bitIndex in 0 ..< field.size {
                let globalBitIndex = bitOffset + bitIndex
                let byteIndex = globalBitIndex / 8
                let bitInByte = globalBitIndex % 8 // LSB first in each byte
                let bitValue = (raw >> UInt64(bitIndex)) & 1
                if bitValue == 1 {
                    buffer[byteIndex] |= (1 << bitInByte)
                }
            }
            bitOffset += field.size
        }
    }

    // MARK: - decode

    public static func decodeIfPossible(from data: Data) -> Self? {
        return try? decode(from: data)
    }

    public static func decodeIfPossible(from bytes: [UInt8]) -> Self? {
        return try? decode(from: bytes)
    }

    public static func decode(from data: Data) throws -> Self {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8
        guard data.count >= totalBytes else {
            throw BitStructDecodingError.insufficientBytes(expected: totalBytes, actual: data.count)
        }

        return decodeFromBytes([UInt8](data))
    }

    public static func decode(from bytes: [UInt8]) throws -> Self {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8
        guard bytes.count >= totalBytes else {
            throw BitStructDecodingError.insufficientBytes(expected: totalBytes, actual: bytes.count)
        }

        return decodeFromBytes(bytes)
    }

    private static func decodeFromBytes(_ bytes: [UInt8]) -> Self {
        var bitOffset = 0
        var result = Self()

        for field in fieldDescriptors {
            if field.size == 0 {
                continue
            }

            if bitOffset % 8 == 0 && field.size % 8 == 0 {
                let byteIndex = bitOffset / 8
                let byteCount = field.size / 8
                var raw: UInt64 = 0
                for byteOffset in 0 ..< byteCount {
                    raw |= UInt64(bytes[byteIndex + byteOffset]) << UInt64(8 * byteOffset)
                }
                field.setter(&result, raw)
                bitOffset += field.size
                continue
            }

            var raw: UInt64 = 0
            for bitIndex in 0 ..< field.size {
                let globalBitIndex = bitOffset + bitIndex
                let byteIndex = globalBitIndex / 8
                let bitInByte = globalBitIndex % 8
                let bitValue = (bytes[byteIndex] >> bitInByte) & 1
                raw |= UInt64(bitValue) << UInt64(bitIndex)
            }
            field.setter(&result, raw)
            bitOffset += field.size
        }

        return result
    }
}
