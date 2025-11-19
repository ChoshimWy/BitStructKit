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
.package(url: "https://github.com/Choshim/BitStructKit.git", from: "0.1.0")
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

Below is an example that mirrors the `DataPacket` C bitfield from the tests. Each descriptor specifies how many bits belong to that property, matching the field declaration order in C.

```swift
import BitStructKit

struct DataPacket: BitStructKit {
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

var packet = DataPacket()
packet.operaType = 0x01
packet.commandType = 0x0C
packet.mode = 0x01

var encoded = packet.encode()
packet.checkSum = encoded.dropFirst().reduce(0, &+)
encoded = packet.encode()

// encoded now matches the Objective-C output 8d00000000000000018c

if let decoded = DataPacket.decode(from: encoded) {
    // Round-trip back into strongly typed fields
}
```

## Development

1. Clone the repository and open it in Xcode or run tests from the command line:

```bash
swift test
```

2. Update the podspec/Package.swift version together when publishing.

## License

BitStructKit is distributed under the MIT license.
