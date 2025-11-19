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

    public init<Value: FixedWidthInteger>(
        keyPath: WritableKeyPath<Root, Value>,
        size: Int
    ) {
        self.size = size
        self.getter = { root in
            UInt64(UInt64(truncatingIfNeeded: root[keyPath: keyPath].magnitude))
        }
        self.setter = { root, raw in
            let masked = raw & ((size >= 64) ? UInt64.max : ((1 << size) - 1))
            root[keyPath: keyPath] = Value(truncatingIfNeeded: masked)
        }
    }
}
