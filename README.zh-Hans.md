# BitStructKit

BitStructKit 是一个轻量级的 Swift 库，用于以声明式方式描述类似 C 位域的比特打包结构，并在 `Data` 与强类型结构之间来回转换。你只需定义字段顺序及其位宽，BitStructKit 就会按可预测的小端位布局完成编码与解码，非常适合固件报文、BLE 协议或其他带宽受限的传输场景。

## 功能特性

- 通过 `BitStructCodable` 协议声明字段，即可完成位域的编码/解码
- 采用可预测的小端位打包规则，可匹配小端目标上常见的 Clang 位域布局
- 总位数会从 `fieldDescriptors` 自动推导，也可以通过 `BitStructLayout.metadata(for:)` 读取完整且只读的布局元数据
- 纯 Swift 实现，无第三方依赖
- 同时支持 Swift Package Manager 与 CocoaPods

## 安装方式

### Swift Package Manager

在 `Package.swift` 中加入依赖：

```swift
.package(url: "https://github.com/ChoshimWy/BitStructKit.git", from: "1.0.2")
```

并在目标中添加 `"BitStructKit"` 作为依赖项。

### CocoaPods

在 `Podfile` 中加入：

```ruby
target 'YourApp' do
    pod 'BitStructKit', '~> 1.0.2'
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

如果你是在迁移现有的 C 位域，可以把 Swift 里的描述符理解成对原始线协议布局的显式声明：

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

关键点是：`fieldDescriptors` 必须按线上真实 bit 流顺序书写，BitStructKit 不会从 Swift 存储属性顺序中自动推导布局。

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
    let decoded = DataPacket.decodeIfPossible(from: payload)
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

BitStructKit 采用由描述符驱动的小端位布局，因此当字段顺序和位宽与 C 实现一致时，编码结果可以与对应的 Objective-C / C 实现保持一致。

### 4. 查看字节布局

对于示例载荷 `8d00000000000000018c`，它展开后的 10 个字节如下：

| 字节 | 位 7...0 | 字段映射 |
| --- | --- | --- |
| 0 | `10001101` | `checkSum` |
| 1 | `00000000` | `reserve[7:0]` |
| 2 | `00000000` | `reserve[15:8]` |
| 3 | `00000000` | `reserve[23:16]` |
| 4 | `00000000` | `reserve[31:24]` |
| 5 | `00000000` | `reserve[39:32]` |
| 6 | `00000000` | `reserve[47:40]` |
| 7 | `00000000` | 第 7 位是 `type`，第 6...0 位是 `reserve[54:48]` |
| 8 | `00000001` | `mode` |
| 9 | `10001100` | 第 7 位是 `operaType`，第 6...0 位是 `commandType` |

BitStructKit 在每个字节内仍然是从最低可用位开始分配字段。上表只是为了便于阅读，按常见的“位 7 到位 0”显示方式展示。

### 5. 查看公开布局元数据

如果你想在不依赖 Swift 存储属性顺序的前提下检查布局，可以直接读取公开元数据：

```swift
let layout = BitStructLayout.metadata(for: DataPacket.self)

print(layout.totalBitCount)                 // 80
print(layout.totalByteCount)                // 10
print(layout.fieldDescriptors.map(\.size)) // [8, 55, 1, 8, 7, 1]
```

`layout.fieldDescriptors` 暴露的是一个只读快照，适合做检查、调试、工具生成或文档展示。你在本地修改这个数组副本，并不会改变源类型声明的实际布局。

## 约束与说明

- `fieldDescriptors` 定义了一条线性的 bit 流；第一个字段先占用最低可用位，后续字段按声明顺序继续向后排列。
- 位序为单字节内小端，布局与小端平台上常见的 Clang 位域结果一致（例如 iOS arm64）。
- 每个字段的 `size` 必须在 0...64 之间，并且 `<= Value.bitWidth`。
- 有符号字段使用补码编码，解码时会进行符号扩展。

## 与 C ABI 的边界

BitStructKit 有意保持简洁，它匹配的是“可视为连续小端 bit 流”的常见 C 位域场景，而不是完整复刻某个 C 编译器的 ABI 规则。

- 它没有 storage unit 对齐或编译器自动插入 padding 的概念，最终布局只由你声明的位宽决定。
- `size == 0` 的描述符会被直接跳过，不会像某些 C ABI 那样强制下一个字段从新的分配边界开始。
- 布局完全由 `fieldDescriptors` 决定，而不是由 Swift 属性声明顺序或运行时反射推导。
- 仅支持最大 64 位的 `FixedWidthInteger` 字段。

如果你是在映射现有的 C 结构，请先确认原始布局没有依赖编译器 pragma、零宽位域、匿名字段或特定目标平台的打包规则。

## 映射现有 C 位域前的检查清单

- 先确认原始编译器和目标平台是小端，或者你已经明确验证过期望的字节序。
- `fieldDescriptors` 要按线上实际 bit 流顺序编写，而不是按业务上更顺手的顺序编写。
- 如果 C 结构里存在显式的保留位或 padding，最好在 Swift 中也把它们写成独立字段，确保整条 bit 流可见。
- 不要默认零宽位域、匿名字段或编译器 packing pragma 可以被直接等价映射。
- 至少添加一个来自 C 实现的固定字节样例测试，以及一个 Swift 侧的 encode/decode 往返测试。

## 错误处理与缓冲区编码

可以使用可抛错的 `decode` 获取失败原因；如果你希望把尾随字节也视为错误，可以改用 `decodeExactly`。另外也可以直接写入字节缓冲区以减少分配：

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

## 开发

1. 克隆仓库并在 Xcode 中打开，或直接执行：

```bash
swift test
```

2. 如果你想比较 `Data` 和 `[UInt8]` 两条 encode / decode 路径的吞吐表现，可以在 release 模式下运行本地 benchmark：

```bash
swift run -c release BitStructKitBenchmarks --iterations 1000000
```

如果你还想和 debug 构建做并排对比，可以去掉 `-c release` 再跑一次。benchmark 输出里会标明当前构建模式。

3. 发布前请同步更新 podspec 与 Package.swift 的版本号。

## 许可证

BitStructKit 以 MIT 许可证发布。
