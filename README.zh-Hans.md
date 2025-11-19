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
.package(url: "https://github.com/Choshim/BitStructKit.git", from: "0.1.0")
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

下面示例与测试用例中的 `DataPacket` 位域保持一致。每个字段的位数与 C 中声明顺序完全相同。

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

// encoded == 8d00000000000000018c，对应 Objective-C 输出

if let decoded = DataPacket.decode(from: encoded) {
    // 成功还原强类型字段
}
```

## 开发

1. 克隆仓库并在 Xcode 中打开，或直接执行：

```bash
swift test
```

2. 发布前请同步更新 podspec 与 Package.swift 的版本号。

## 许可证

BitStructKit 以 MIT 许可证发布。
