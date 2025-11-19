# BitStructKit

BitStructKit 是一个轻量级的 Swift 库，用于以声明式方式描述类似 C 位域的比特打包结构，并在 `Data` 与强类型结构之间来回转换。你只需定义字段顺序及其位宽，BitStructKit 就会按照 Clang 位域的排列方式自动完成编码与解码，非常适合固件报文、BLE 协议或其他带宽受限的传输场景。

## 功能特性

- 通过 `BitStructKit` 协议声明字段，即可完成位域的编码/解码
- 按照 Clang 的小端位域规则打包，可与 C 结构无缝互操作
- 纯 Swift 实现，无第三方依赖
- 同时支持 Swift Package Manager 与 CocoaPods

## 安装方式

### Swift Package Manager

在 `Package.swift` 中加入依赖：

```swift
.package(url: "https://github.com/ChoshimWy/BitStructKit.git", from: "0.1.0")
```

并在目标中添加 `"BitStructKit"` 作为依赖项。

### CocoaPods

在 `Podfile` 中加入：

```ruby
target 'YourApp' do
  pod 'BitStructKit', '~> 0.1.0'
end
```

随后执行 `pod install`。

## 使用示例

以下示例与测试用例中的 `DataPacket` 位域完全一致，展示了如何描述结构、解析十六进制数据、再重新写回字节流。

### 1. 定义位域结构

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

### 2. 解析 Objective-C 生成的十六进制报文

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
    fatalError("无效报文")
}

print(decoded.mode)        // 0x01
print(decoded.commandType) // 0x0C
print(decoded.operaType)   // 0x01
```

### 3. 修改字段并重新编码

```swift
var packet = decoded
packet.mode = 0x02

var encoded = packet.encode()
packet.checkSum = encoded.dropFirst().reduce(0, &+)
encoded = packet.encode()

print(encoded.hexString) // 仍遵循相同的位域布局
```

BitStructKit 与 Clang 位域保持一致，因此编码结果能够与 Objective-C/ C 的实现严格匹配。

## 开发

1. 克隆仓库并在 Xcode 中打开，或直接执行：

```bash
swift test
```

2. 发布前请同步更新 podspec 与 Package.swift 的版本号。

## 许可证

BitStructKit 以 MIT 许可证发布。
