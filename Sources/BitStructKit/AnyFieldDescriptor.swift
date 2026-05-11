//
//  AnyFieldDescriptor.swift
//  BitStructKit
//
//  Created by Choshim.Wei on 2025/11/19.
//  Copyright © 2025 Choshim.Wei. All rights reserved.
//

import Foundation

/// A type-erased field descriptor that maps a property on `Root` to a raw `UInt64` bitfield value.
///
/// `AnyFieldDescriptor` stores the declared field width together with getter and setter closures.
/// This lets the encoder and decoder operate on a uniform `UInt64` representation while the
/// actual stored property can remain any `FixedWidthInteger` type.
public struct AnyFieldDescriptor<Root>: @unchecked Sendable {
    /// Number of bits occupied by this field in the serialized layout.
    public let size: Int
    /// Reads the field from `Root` and converts it to a raw `UInt64` representation.
    public let getter: (Root) -> UInt64
    /// Writes a raw `UInt64` value back into `Root`, applying masking and sign extension as needed.
    public let setter: (inout Root, UInt64) -> Void

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

    /// Creates a descriptor for an integer property with the given serialized bit width.
    ///
    /// The stored property type may be wider than `size`; in that case encoding truncates to the
    /// declared field width, and decoding masks the raw value back to that width. Signed integer
    /// fields smaller than the property width are sign-extended on decode so two's-complement
    /// semantics match the serialized bit pattern.
    public init<Value: FixedWidthInteger>(
        keyPath: WritableKeyPath<Root, Value>,
        size: Int
    ) {
        precondition(size >= 0 && size <= 64, "size must be within 0...64")
        precondition(size <= Value.bitWidth, "size must be <= Value.bitWidth")

        self.size = size
        self.getter = { root in
            UInt64(truncatingIfNeeded: root[keyPath: keyPath])
        }
        self.setter = { root, raw in
            let masked = raw & AnyFieldDescriptor.mask(for: size)
            if Value.isSigned && size > 0 && size < Value.bitWidth {
                // Recreate the high bits of a narrower signed field before truncating back to Value.
                let signBit = UInt64(1) << UInt64(size - 1)
                let extended = (masked & signBit) != 0
                    ? (masked | ~AnyFieldDescriptor.mask(for: size))
                    : masked
                root[keyPath: keyPath] = Value(truncatingIfNeeded: extended)
            } else {
                root[keyPath: keyPath] = Value(truncatingIfNeeded: masked)
            }
        }
    }
}
