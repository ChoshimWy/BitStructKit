//
//  BitStructKit.swift
//  BitStructKit
//
//  Created by Choshim.Wei on 2025/11/19.
//  Copyright © 2025 Choshim.Wei. All rights reserved.
//

import Foundation

// MARK: - BitStructCodable

/// Describes a bit-packed Swift type whose layout is fully defined by `fieldDescriptors`.
public protocol BitStructCodable {
    /// Creates an empty instance used as the decode target before descriptors apply values.
    init()
    /// Field descriptors must be declared in wire-order.
    static var fieldDescriptors: [AnyFieldDescriptor<Self>] { get }
}

public enum BitStructDecodingError: Error, Equatable {
    /// The input buffer is shorter than the number of bytes required by the declared layout.
    case insufficientBytes(expected: Int, actual: Int)
    /// Strict decoding was requested, but the input contains trailing bytes beyond the declared layout.
    case trailingBytes(expected: Int, actual: Int)
}

/// Public metadata helpers for inspecting a type's declared bit layout.
public enum BitStructLayout {
    /// A read-only snapshot of the layout declared by a `BitStructCodable` type.
    public struct Metadata<Root: BitStructCodable>: @unchecked Sendable {
        /// Descriptor metadata exposed for inspection, debugging, or documentation.
        /// Mutating a local copy of this array does not change the source type's layout.
        public let fieldDescriptors: [AnyFieldDescriptor<Root>]
        /// Total number of bits occupied by the declared descriptors.
        public let totalBitCount: Int
        /// Total number of bytes required to store the declared bit stream.
        public let totalByteCount: Int
    }

    /// Returns a stable metadata snapshot derived from `fieldDescriptors`.
    public static func metadata<T: BitStructCodable>(for type: T.Type) -> Metadata<T> {
        let fieldDescriptors = type.fieldDescriptors
        let totalBitCount = fieldDescriptors.reduce(0) { $0 + $1.size }
        return Metadata(
            fieldDescriptors: fieldDescriptors,
            totalBitCount: totalBitCount,
            totalByteCount: (totalBitCount + 7) / 8
        )
    }

    /// Convenience accessor for the descriptor snapshot.
    public static func fieldDescriptors<T: BitStructCodable>(for type: T.Type) -> [AnyFieldDescriptor<T>] {
        metadata(for: type).fieldDescriptors
    }

    /// Convenience accessor for the derived bit count.
    public static func totalBitCount<T: BitStructCodable>(for type: T.Type) -> Int {
        metadata(for: type).totalBitCount
    }

    /// Convenience accessor for the derived byte count.
    public static func totalByteCount<T: BitStructCodable>(for type: T.Type) -> Int {
        metadata(for: type).totalByteCount
    }
}

extension BitStructCodable {
    @available(*, deprecated, message: "Use BitStructLayout.metadata(for:).totalBitCount for a stable layout query.")
    public static var totalBitCount: Int {
        BitStructLayout.metadata(for: Self.self).totalBitCount
    }

    /// Captures the current descriptor list once per operation so encoding and decoding
    /// work against a single consistent layout snapshot.
    private static func resolvedLayout() -> BitStructLayout.Metadata<Self> {
        BitStructLayout.metadata(for: Self.self)
    }

    /// Returns a bitmask with the lowest `size` bits set.
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

    /// Encodes the receiver into a newly allocated `Data` buffer.
    public func encode() -> Data {
        var data = Data()
        encode(into: &data)
        return data
    }

    /// Encodes the receiver into a `Data` buffer, resizing it if needed.
    public func encode(into data: inout Data) {
        let layout = Self.resolvedLayout()
        let totalBytes = layout.totalByteCount

        if data.count != totalBytes {
            data = Data(count: totalBytes)
        }

        data.withUnsafeMutableBytes { rawBuffer in
            let byteBuffer = rawBuffer.bindMemory(to: UInt8.self)
            encode(into: byteBuffer, fields: layout.fieldDescriptors)
        }
    }

    /// Encodes the receiver into a byte array, resizing it if needed.
    public func encode(into buffer: inout [UInt8]) {
        let layout = Self.resolvedLayout()
        let totalBytes = layout.totalByteCount

        if buffer.count != totalBytes {
            buffer = [UInt8](repeating: 0, count: totalBytes)
        }

        buffer.withUnsafeMutableBufferPointer { rawBuffer in
            encode(into: rawBuffer, fields: layout.fieldDescriptors)
        }
    }

    private func encode(
        into buffer: UnsafeMutableBufferPointer<UInt8>,
        fields: [AnyFieldDescriptor<Self>]
    ) {
        for index in buffer.indices {
            buffer[index] = 0
        }

        var bitOffset = 0 // Number of bits already written, progressing from LSB to MSB.

        for field in fields {
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

            // Write the field's low `size` bits starting at `bitOffset` using little-endian bit ordering.
            for bitIndex in 0 ..< field.size {
                let globalBitIndex = bitOffset + bitIndex
                let byteIndex = globalBitIndex / 8
                let bitInByte = globalBitIndex % 8 // LSB-first within each byte.
                let bitValue = (raw >> UInt64(bitIndex)) & 1
                if bitValue == 1 {
                    buffer[byteIndex] |= (1 << bitInByte)
                }
            }
            bitOffset += field.size
        }
    }

    // MARK: - decode

    /// Attempts to decode from `Data`, returning `nil` on failure.
    public static func decodeIfPossible(from data: Data) -> Self? {
        return try? decode(from: data)
    }

    /// Attempts to decode from a byte array, returning `nil` on failure.
    public static func decodeIfPossible(from bytes: [UInt8]) -> Self? {
        return try? decode(from: bytes)
    }

    /// Attempts to strictly decode from `Data`, returning `nil` on failure.
    public static func decodeIfPossibleExactly(from data: Data) -> Self? {
        return try? decodeExactly(from: data)
    }

    /// Attempts to strictly decode from a byte array, returning `nil` on failure.
    public static func decodeIfPossibleExactly(from bytes: [UInt8]) -> Self? {
        return try? decodeExactly(from: bytes)
    }

    /// Decodes from `Data`, allowing trailing bytes as long as the declared layout fits.
    public static func decode(from data: Data) throws -> Self {
        let layout = Self.resolvedLayout()
        let totalBytes = layout.totalByteCount
        guard data.count >= totalBytes else {
            throw BitStructDecodingError.insufficientBytes(expected: totalBytes, actual: data.count)
        }

        return data.withUnsafeBytes { rawBuffer in
            decodeFromBytes(rawBuffer.bindMemory(to: UInt8.self), fields: layout.fieldDescriptors)
        }
    }

    /// Decodes from a byte array, allowing trailing bytes as long as the declared layout fits.
    public static func decode(from bytes: [UInt8]) throws -> Self {
        let layout = Self.resolvedLayout()
        let totalBytes = layout.totalByteCount
        guard bytes.count >= totalBytes else {
            throw BitStructDecodingError.insufficientBytes(expected: totalBytes, actual: bytes.count)
        }

        return bytes.withUnsafeBufferPointer { rawBuffer in
            decodeFromBytes(rawBuffer, fields: layout.fieldDescriptors)
        }
    }

    /// Decodes from `Data` and rejects any trailing bytes beyond the declared layout.
    public static func decodeExactly(from data: Data) throws -> Self {
        let layout = Self.resolvedLayout()
        let totalBytes = layout.totalByteCount
        guard data.count >= totalBytes else {
            throw BitStructDecodingError.insufficientBytes(expected: totalBytes, actual: data.count)
        }
        guard data.count == totalBytes else {
            throw BitStructDecodingError.trailingBytes(expected: totalBytes, actual: data.count)
        }

        return data.withUnsafeBytes { rawBuffer in
            decodeFromBytes(rawBuffer.bindMemory(to: UInt8.self), fields: layout.fieldDescriptors)
        }
    }

    /// Decodes from a byte array and rejects any trailing bytes beyond the declared layout.
    public static func decodeExactly(from bytes: [UInt8]) throws -> Self {
        let layout = Self.resolvedLayout()
        let totalBytes = layout.totalByteCount
        guard bytes.count >= totalBytes else {
            throw BitStructDecodingError.insufficientBytes(expected: totalBytes, actual: bytes.count)
        }
        guard bytes.count == totalBytes else {
            throw BitStructDecodingError.trailingBytes(expected: totalBytes, actual: bytes.count)
        }

        return bytes.withUnsafeBufferPointer { rawBuffer in
            decodeFromBytes(rawBuffer, fields: layout.fieldDescriptors)
        }
    }

    private static func decodeFromBytes(
        _ bytes: UnsafeBufferPointer<UInt8>,
        fields: [AnyFieldDescriptor<Self>]
    ) -> Self {
        var bitOffset = 0
        var result = Self()

        for field in fields {
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

            // Rebuild the field value by reading bits from the byte stream in LSB-first order.
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
