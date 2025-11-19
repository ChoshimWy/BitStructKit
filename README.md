# BitStructKit

> [中文说明](README.zh-Hans.md)

BitStructKit is a tiny Swift library that lets you describe bit-packed payloads (similar to C bitfields) and serialize them to and from `Data`. Define your struct, provide field descriptors with individual bit widths, and BitStructKit handles the packing order—perfect for firmware packets, BLE protocols, or any space constrained wire format.

## Features

- Declarative encoding/decoding of bitfields using `BitStructKit` protocol
- Mirrors Clang's little-endian bitfield layout for painless interop with C structs
- Pure Swift implementation with zero dependencies
- Works with Swift Package Manager or CocoaPods

## Installation

### Swift Package Manager

Add BitStructKit to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/ChoshimWy/BitStructKit.git", from: "0.1.0")
```

Then add `"BitStructKit"` to the target dependencies that need it.

### CocoaPods

Add the pod to your `Podfile` and run `pod install`:

```ruby
target 'YourApp' do
  pod 'BitStructKit', '~> 0.1.0'
end
```

## Usage

The example below mirrors the Objective‑C `DataPacket` bitfield that produced the `8d00000000000000018c` payload. The steps are always the same: describe your layout, decode raw bytes, optionally mutate fields, then re‑encode.

### 1. Describe the bit layout

```swift
import BitStructKit

struct DataPacket: BitStructCodable {
    var checkSum: UInt8 = 0
    var reserve: UInt64 = 0
    var type: UInt8 = 0
    var mode: UInt8 = 0
    var commandType: UInt8 = 0
    var operaType: UInt8 = 0

    static var fieldDescriptors: [AnyFieldDescriptor<DataPacket>] {
        [
            AnyFieldDescriptor(keyPath: \.checkSum, size: 8),
            AnyFieldDescriptor(keyPath: \.reserve, size: 55),
            AnyFieldDescriptor(keyPath: \.type, size: 1),
            AnyFieldDescriptor(keyPath: \.mode, size: 8),
            AnyFieldDescriptor(keyPath: \.commandType, size: 7),
            AnyFieldDescriptor(keyPath: \.operaType, size: 1),
        ]
    }
}
```

### 2. Decode existing bytes (e.g. Objective‑C payload)

```swift
let hexPayload = "8d00000000000000018c"

extension Data {
    init?(hexString: String) {
        let clean = hexString.replacingOccurrences(of: " ", with: "")
        guard clean.count % 2 == 0 else { return nil }

        var bytes = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let value = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        self = bytes
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

guard
    let payload = Data(hexString: hexPayload),
    let decoded = DataPacket.decode(from: payload)
else {
    fatalError("Invalid payload")
}

print(decoded.mode)        // 0x01
print(decoded.commandType) // 0x0C
print(decoded.operaType)   // 0x01
```

### 3. Mutate fields and re‑encode

```swift
var packet = decoded
packet.mode = 0x02

var encoded = packet.encode()
packet.checkSum = encoded.dropFirst().reduce(0, &+)
encoded = packet.encode()

print(encoded.hexString) // Still uses the same bit layout
```

Because BitStructKit packs bits exactly like Clang, the resulting bytes match the ones produced by the C implementation.

## Development

1. Clone the repository and open it in Xcode or run tests from the command line:

```bash
swift test
```

2. Update the podspec/Package.swift version together when publishing.

## License

BitStructKit is distributed under the MIT license.
