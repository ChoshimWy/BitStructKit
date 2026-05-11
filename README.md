# BitStructKit

> [中文说明](README.zh-Hans.md)

BitStructKit is a tiny Swift library for describing and encoding bit-packed payloads in Swift using a layout similar to C bitfields. Define your struct, provide field descriptors with individual bit widths, and BitStructKit will pack and unpack `Data` using a predictable little-endian bit layout. It is a good fit for firmware packets, BLE protocols, and other space-constrained wire formats.

## Features

- Declarative encoding/decoding of bitfields using the `BitStructCodable` protocol
- Predictable little-endian bit packing that matches common Clang bitfield layouts on little-endian targets
- Total layout size is derived from `fieldDescriptors`, and full read-only layout metadata is available via `BitStructLayout.metadata(for:)`
- Pure Swift implementation with zero dependencies
- Works with Swift Package Manager or CocoaPods

## Installation

### Swift Package Manager

Add BitStructKit to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/ChoshimWy/BitStructKit.git", from: "1.0.3")
```

Then add `"BitStructKit"` to the target dependencies that need it.

### CocoaPods

Add the pod to your `Podfile` and run `pod install`:

```ruby
target 'YourApp' do
    pod 'BitStructKit', '~> 1.0.3'
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

If you are porting an existing C bitfield, think of the Swift descriptors as an explicit wire-layout declaration for the original definition:

```c
typedef struct {
    uint8_t  check_sum:8;
    uint64_t reserve:55;
    uint8_t  type:1;
    uint8_t  mode:8;
    uint8_t  command_type:7;
    uint8_t  opera_type:1;
} DataPacket;
```

```swift
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
```

The important rule is that `fieldDescriptors` must be written in wire order. BitStructKit does not infer this order from the Swift stored properties.

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
    let decoded = DataPacket.decodeIfPossible(from: payload)
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

Because BitStructKit uses a descriptor-driven little-endian bit layout, the resulting bytes can match the ones produced by the corresponding C implementation when the field order and widths are the same.

### 4. Inspect the byte layout

For the example payload `8d00000000000000018c`, the 10-byte layout looks like this:

| Byte | Bits 7...0 | Field mapping |
| --- | --- | --- |
| 0 | `10001101` | `checkSum` |
| 1 | `00000000` | `reserve[7:0]` |
| 2 | `00000000` | `reserve[15:8]` |
| 3 | `00000000` | `reserve[23:16]` |
| 4 | `00000000` | `reserve[31:24]` |
| 5 | `00000000` | `reserve[39:32]` |
| 6 | `00000000` | `reserve[47:40]` |
| 7 | `00000000` | bit 7 = `type`, bits 6...0 = `reserve[54:48]` |
| 8 | `00000001` | `mode` |
| 9 | `10001100` | bit 7 = `operaType`, bits 6...0 = `commandType` |

BitStructKit still assigns fields from the least-significant available bit in each byte. The table above is simply shown in the conventional bit 7 to bit 0 reading order.

### 5. Inspect public layout metadata

You can inspect the declared layout without relying on the type's stored-property order:

```swift
let layout = BitStructLayout.metadata(for: DataPacket.self)

print(layout.totalBitCount)            // 80
print(layout.totalByteCount)           // 10
print(layout.fieldDescriptors.map(\.size)) // [8, 55, 1, 8, 7, 1]
```

`layout.fieldDescriptors` is exposed as a read-only snapshot for inspection, debugging, tooling, or documentation generation. Mutating a local copy does not change the source type's declared layout.

## Notes and constraints

- Field descriptors define a single linear bit stream. The first descriptor occupies the lowest available bits, then packing continues in declaration order.
- Bit order is little-endian within each byte, matching common Clang bitfield layouts on little-endian targets (e.g. iOS arm64).
- Each descriptor `size` must be within 0...64 and `<= Value.bitWidth`.
- Signed fields use two's complement encoding and sign-extend on decode.

## ABI compatibility boundaries

BitStructKit is intentionally simpler than a full C compiler ABI implementation. It matches the common case where a C bitfield can be treated as a contiguous little-endian bit stream, but it does not model every compiler-specific rule.

- There is no concept of storage-unit alignment or compiler-inserted padding beyond the bit widths you declare.
- A descriptor with `size == 0` is simply skipped; it does not force the next field onto a new allocation boundary like some C bitfield ABIs do.
- The layout is fully driven by `fieldDescriptors`, not by Swift property declaration order or runtime reflection.
- Only `FixedWidthInteger` fields up to 64 bits are supported.

If you are mirroring an existing C struct, verify that the original layout does not depend on compiler pragmas, zero-width bitfields, anonymous fields, or target-specific packing rules.

## Checklist for mirroring an existing C bitfield

- Confirm the original compiler and target are little-endian, or that you have explicitly validated the expected byte order.
- Write `fieldDescriptors` in wire-order, not in whatever order happens to be most convenient in business logic.
- Represent explicit reserved or padding bits as dedicated fields so the full bit stream remains visible in Swift.
- Do not assume zero-width bitfields, anonymous fields, or compiler packing pragmas will translate directly.
- Add at least one fixture test with bytes produced by the C implementation, plus one round-trip encode/decode test on the Swift side.

## Error handling and buffers

You can use the throwing `decode` to get a reason when decoding fails, use `decodeExactly` when trailing bytes should be rejected, and encode directly into a byte buffer to avoid extra allocations:

```swift
do {
    let packet = try DataPacket.decode(from: payload)
    print(packet)
} catch {
    print(error)
}

do {
    let exactPacket = try DataPacket.decodeExactly(from: payload)
    print(exactPacket)
} catch {
    print(error)
}

var buffer = [UInt8]()
decoded.encode(into: &buffer)
```

## Development

1. Clone the repository and open it in Xcode or run tests from the command line:

```bash
swift test
```

2. Run the local benchmark in release mode when you want to compare `Data` and `[UInt8]` encode/decode throughput:

```bash
swift run -c release BitStructKitBenchmarks --iterations 1000000
```

Run the same command without `-c release` if you want a debug build for side-by-side comparison. The benchmark output includes the current build mode.

3. Update the podspec/Package.swift version together when publishing.

## License

BitStructKit is distributed under the MIT license.
