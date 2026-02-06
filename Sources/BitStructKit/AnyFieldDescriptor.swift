//
//  AnyFieldDescriptor.swift
//  BitStructKit
//
//  Created by Choshim.Wei on 2025/11/19.
//  Copyright © 2025 Choshim.Wei. All rights reserved.
//

import Foundation

/// 类型擦除的字段描述符(每个字段负责把字段值 <-> UInt64)
public struct AnyFieldDescriptor<Root> {
    public let size: Int
    public let getter: (Root) -> UInt64
    public let setter: (inout Root, UInt64) -> Void

    private static func mask(for size: Int) -> UInt64 {
        if size >= 64 {
            return UInt64.max
        }
        if size <= 0 {
            return 0
        }
        return (1 << size) - 1
    }

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
