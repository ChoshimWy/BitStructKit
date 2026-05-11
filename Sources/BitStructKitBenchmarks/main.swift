import BitStructKit
import Dispatch
import Foundation

struct BenchmarkPacket: BitStructCodable {
    var checkSum: UInt8 = 0x8D
    var reserve: UInt64 = 0
    var type: UInt8 = 0
    var mode: UInt8 = 0x01
    var commandType: UInt8 = 0x0C
    var operaType: UInt8 = 0x01

    static let fieldDescriptors: [AnyFieldDescriptor<BenchmarkPacket>] = [
            AnyFieldDescriptor(keyPath: \.checkSum, size: 8),
            AnyFieldDescriptor(keyPath: \.reserve, size: 55),
            AnyFieldDescriptor(keyPath: \.type, size: 1),
            AnyFieldDescriptor(keyPath: \.mode, size: 8),
            AnyFieldDescriptor(keyPath: \.commandType, size: 7),
            AnyFieldDescriptor(keyPath: \.operaType, size: 1)
    ]
}

struct BenchmarkConfiguration {
    var iterations: Int = 200_000
}

struct BenchmarkResult {
    let name: String
    let iterations: Int
    let bytesPerIteration: Int
    let elapsedNanoseconds: UInt64

    var nanosecondsPerOperation: Double {
        Double(elapsedNanoseconds) / Double(iterations)
    }

    var megabytesPerSecond: Double {
        let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
        guard elapsedSeconds > 0 else {
            return .infinity
        }

        let totalMegabytes = (Double(bytesPerIteration) * Double(iterations)) / 1_000_000
        return totalMegabytes / elapsedSeconds
    }
}

private let currentBuildConfiguration: String = {
#if DEBUG
    return "debug"
#else
    return "release"
#endif
}()

enum BenchmarkCLIError: Error, CustomStringConvertible {
    case invalidIterations(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .invalidIterations(value):
            return "Invalid iteration count: \(value)"
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)"
        }
    }
}

private func parseConfiguration() throws -> BenchmarkConfiguration {
    var configuration = BenchmarkConfiguration()
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--iterations", "-n":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw BenchmarkCLIError.invalidIterations("<missing>")
            }
            guard let iterations = Int(arguments[valueIndex]), iterations > 0 else {
                throw BenchmarkCLIError.invalidIterations(arguments[valueIndex])
            }
            configuration.iterations = iterations
            index += 2
        case "--help", "-h":
            printUsage()
            Foundation.exit(EXIT_SUCCESS)
        default:
            throw BenchmarkCLIError.unknownArgument(argument)
        }
    }

    return configuration
}

private func printUsage() {
    print("Usage: swift run -c release BitStructKitBenchmarks --iterations 1000000")
    print("  -n, --iterations   Number of iterations to run for each benchmark")
}

private func runBenchmark(
    name: String,
    iterations: Int,
    bytesPerIteration: Int,
    body: () throws -> Void
) rethrows -> BenchmarkResult {
    let start = DispatchTime.now().uptimeNanoseconds
    try body()
    let end = DispatchTime.now().uptimeNanoseconds

    return BenchmarkResult(
        name: name,
        iterations: iterations,
        bytesPerIteration: bytesPerIteration,
        elapsedNanoseconds: end - start
    )
}

private enum ColumnAlignment {
    case left
    case right
}

private func padded(_ value: String, to width: Int, alignment: ColumnAlignment) -> String {
    let padding = max(0, width - value.count)
    guard padding > 0 else {
        return value
    }

    let spaces = String(repeating: " ", count: padding)
    switch alignment {
    case .left:
        return value + spaces
    case .right:
        return spaces + value
    }
}

private func printResultsTable(_ results: [BenchmarkResult]) {
    let nameWidth = max(results.map { $0.name.count }.max() ?? 0, "Benchmark".count)
    let iterationsWidth = max(results.map { String($0.iterations).count }.max() ?? 0, "Iterations".count)
    let nsWidth = max(results.map { String(format: "%.2f", $0.nanosecondsPerOperation).count }.max() ?? 0, "ns/op".count)
    let mbWidth = max(results.map { String(format: "%.2f", $0.megabytesPerSecond).count }.max() ?? 0, "MB/s".count)

    let header = [
        padded("Benchmark", to: nameWidth, alignment: .left),
        padded("Iterations", to: iterationsWidth, alignment: .right),
        padded("ns/op", to: nsWidth, alignment: .right),
        padded("MB/s", to: mbWidth, alignment: .right)
    ].joined(separator: "  ")
    print(header)
    print(String(repeating: "-", count: header.count))

    for result in results {
        let nsPerOperation = String(format: "%.2f", result.nanosecondsPerOperation)
        let megabytesPerSecond = String(format: "%.2f", result.megabytesPerSecond)
        let line = [
            padded(result.name, to: nameWidth, alignment: .left),
            padded(String(result.iterations), to: iterationsWidth, alignment: .right),
            padded(nsPerOperation, to: nsWidth, alignment: .right),
            padded(megabytesPerSecond, to: mbWidth, alignment: .right)
        ].joined(separator: "  ")
        print(line)
    }
}

do {
    let configuration = try parseConfiguration()
    let iterations = configuration.iterations
    var benchmarkSink: UInt64 = 0

    @inline(never)
    func consume(_ value: UInt64) {
        benchmarkSink = benchmarkSink &+ value
    }

    @inline(never)
    func consume(_ data: Data) {
        consume(UInt64(data.count))
        consume(UInt64(data.first ?? 0))
        consume(UInt64(data.last ?? 0))
    }

    @inline(never)
    func consume(_ bytes: [UInt8]) {
        consume(UInt64(bytes.count))
        consume(UInt64(bytes.first ?? 0))
        consume(UInt64(bytes.last ?? 0))
    }

    @inline(never)
    func consume(_ packet: BenchmarkPacket) {
        consume(UInt64(packet.checkSum))
        consume(packet.reserve)
        consume(UInt64(packet.type))
        consume(UInt64(packet.mode))
        consume(UInt64(packet.commandType))
        consume(UInt64(packet.operaType))
    }

    var packet = BenchmarkPacket()
    packet.reserve = 0x0012_3456_789A_BCDE & ((1 << 55) - 1)
    let payload = packet.encode()
    let payloadBytes = [UInt8](payload)
    let bytesPerIteration = payload.count
    var results: [BenchmarkResult] = []

    print("BitStructKit benchmark")
    print("Build: \(currentBuildConfiguration)")
    print("Iterations: \(iterations)")
    print("Payload bytes: \(bytesPerIteration)")

    let encodeResult = runBenchmark(
        name: "encode() -> Data",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        for _ in 0 ..< iterations {
            let encoded = packet.encode()
            consume(encoded)
        }
    }
    results.append(encodeResult)

    let encodeIntoDataResult = runBenchmark(
        name: "encode(into: Data)",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        var reusableData = Data()
        for _ in 0 ..< iterations {
            packet.encode(into: &reusableData)
            consume(reusableData)
        }
    }
    results.append(encodeIntoDataResult)

    let encodeIntoBytesResult = runBenchmark(
        name: "encode(into: [UInt8])",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        var reusableBytes: [UInt8] = []
        for _ in 0 ..< iterations {
            packet.encode(into: &reusableBytes)
            consume(reusableBytes)
        }
    }
    results.append(encodeIntoBytesResult)

    let decodeResult = try runBenchmark(
        name: "decode(from: Data)",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        for _ in 0 ..< iterations {
            let decoded = try BenchmarkPacket.decode(from: payload)
            consume(decoded)
        }
    }
    results.append(decodeResult)

    let decodeBytesResult = try runBenchmark(
        name: "decode(from: [UInt8])",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        for _ in 0 ..< iterations {
            let decoded = try BenchmarkPacket.decode(from: payloadBytes)
            consume(decoded)
        }
    }
    results.append(decodeBytesResult)

    let decodeExactlyResult = try runBenchmark(
        name: "decodeExactly(from: Data)",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        for _ in 0 ..< iterations {
            let decoded = try BenchmarkPacket.decodeExactly(from: payload)
            consume(decoded)
        }
    }
    results.append(decodeExactlyResult)

    let decodeExactlyBytesResult = try runBenchmark(
        name: "decodeExactly(from: [UInt8])",
        iterations: iterations,
        bytesPerIteration: bytesPerIteration
    ) {
        for _ in 0 ..< iterations {
            let decoded = try BenchmarkPacket.decodeExactly(from: payloadBytes)
            consume(decoded)
        }
    }
    results.append(decodeExactlyBytesResult)

    printResultsTable(results)

    print("Sink: \(benchmarkSink)")
} catch {
    fputs("\(error)\n", stderr)
    printUsage()
    Foundation.exit(EXIT_FAILURE)
}