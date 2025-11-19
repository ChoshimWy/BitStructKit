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

extension BitStructCodable {
    public static var totalBitCount: Int {
        fieldDescriptors.reduce(0) { $0 + $1.size }
    }

    // MARK: - encode -> Data (little-endian bit packing like Clang bitfields)

    public func encode() -> Data {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8

        var buffer = [UInt8](repeating: 0, count: totalBytes)
        var bitOffset = 0 // 已写入位数，从 LSB -> MSB

        for field in Self.fieldDescriptors {
            let raw = field.getter(self) & ((field.size >= 64) ? UInt64.max : ((1 << field.size) - 1))
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
        return Data(buffer)
    }

    // MARK: - decode

    public static func decode(from data: Data) -> Self? {
        let totalBits = Self.totalBitCount
        let totalBytes = (totalBits + 7) / 8
        guard data.count >= totalBytes else { return nil }

        let bytes = [UInt8](data)

        var bitOffset = 0
        var result = Self()

        for field in fieldDescriptors {
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
