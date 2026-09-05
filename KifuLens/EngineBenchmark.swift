import Darwin
import Foundation
import UIKit

struct EngineBenchmarkPosition: Equatable {
    let index: Int
    let sfen: String
}

enum EngineBenchmarkConfiguration {
    static let moveTimeMilliseconds = 5_000
    static let buildVariant = "ios-dotprod-a13-lto-prefetch"
    static let positions = [
        EngineBenchmarkPosition(
            index: 1,
            sfen: "lnsgkgsnl/1r7/p1ppp1bpp/1p3pp2/7P1/2P6/"
                + "PP1PPPP1P/1B3S1R1/LNSGKG1NL b - 9"
        ),
        EngineBenchmarkPosition(
            index: 2,
            sfen: "l4S2l/4g1gs1/5p1p1/pr2N1pkp/4Gn3/PP3PPPP/"
                + "2GPP4/1K7/L3r+s2L w BS2N5Pb 1"
        ),
        EngineBenchmarkPosition(
            index: 3,
            sfen: "6n1l/2+S1k4/2lp4p/1np1B2b1/3PP4/1N1S3rP/"
                + "1P2+pPP+p1/1p1G5/3KG2r1 b GSN2L4Pgs2p 1"
        ),
        EngineBenchmarkPosition(
            index: 4,
            sfen: "l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/"
                + "P5GS1/R8/LN4bKL w RGgsn5p 1"
        ),
    ]

    static func command(for settings: AnalysisSettings) -> String {
        "bench \(settings.hashSizeMB) \(settings.threadCount) "
            + "\(moveTimeMilliseconds) default movetime"
    }
}

struct EngineBenchmarkPositionResult: Codable, Equatable, Identifiable {
    let index: Int
    let sfen: String
    let depth: Int
    let seldepth: Int
    let nodes: UInt64
    let nps: UInt64
    let timeMilliseconds: Int
    let hashfull: Int
    let score: String?
    let principalVariation: [String]
    let bestmove: String
    let ponder: String?

    var id: Int { index }
}

struct EngineBenchmarkMeasurement: Equatable {
    let startedAt: Date
    let finishedAt: Date
    let engine: AnalysisEngineDescriptor
    let configuration: AnalysisSettings
    let command: String
    let buildVariant: String
    let depthLimit: Int?
    let totalTimeMilliseconds: Int
    let totalNodes: UInt64
    let nodesPerSecond: UInt64
    let positions: [EngineBenchmarkPositionResult]
    let rawTranscript: [String]
    let progressAsset: String
    let bucketMode: String
}

struct EngineBenchmarkEnvironment: Equatable {
    let deviceIdentifier: String
    let cpuFamily: String
    let operatingSystem: String
    let thermalState: String
    let lowPowerModeEnabled: Bool

    static var current: EngineBenchmarkEnvironment {
        EngineBenchmarkEnvironment(
            deviceIdentifier: machineIdentifier,
            cpuFamily: KifuLensDeviceSupport.currentCPUFamily.map {
                String(format: "0x%08x", $0)
            } ?? "取得不可",
            operatingSystem:
                "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            thermalState: ProcessInfo.processInfo.thermalState.benchmarkText,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}

struct EngineBenchmarkRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let engineIdentifier: String
    let engineName: String
    let engineVersion: String
    let buildVariant: String
    let command: String
    let threadCount: Int
    let hashSizeMB: Int
    let depthLimit: Int?
    let nodesPerPosition: UInt64?
    let totalTimeMilliseconds: Int
    let totalNodes: UInt64
    let nodesPerSecond: UInt64
    let positions: [EngineBenchmarkPositionResult]
    let deviceIdentifier: String
    let cpuFamily: String
    let operatingSystem: String
    let appVersion: String
    let appBuild: String
    let startingThermalState: String
    let endingThermalState: String
    let startingLowPowerModeEnabled: Bool
    let endingLowPowerModeEnabled: Bool
    let progressAsset: String
    let bucketMode: String
    let rawTranscript: [String]

    init(
        measurement: EngineBenchmarkMeasurement,
        startingEnvironment: EngineBenchmarkEnvironment,
        endingEnvironment: EngineBenchmarkEnvironment,
        bundle: Bundle = .main
    ) {
        let info = bundle.infoDictionary
        id = UUID()
        startedAt = measurement.startedAt
        finishedAt = measurement.finishedAt
        engineIdentifier = measurement.engine.id.rawValue
        engineName = measurement.engine.displayName
        engineVersion = measurement.engine.version
        buildVariant = measurement.buildVariant
        command = measurement.command
        threadCount = measurement.configuration.threadCount
        hashSizeMB = measurement.configuration.hashSizeMB
        depthLimit = measurement.depthLimit
        nodesPerPosition = nil
        totalTimeMilliseconds = measurement.totalTimeMilliseconds
        totalNodes = measurement.totalNodes
        nodesPerSecond = measurement.nodesPerSecond
        positions = measurement.positions
        deviceIdentifier = startingEnvironment.deviceIdentifier
        cpuFamily = startingEnvironment.cpuFamily
        operatingSystem = startingEnvironment.operatingSystem
        appVersion = info?["CFBundleShortVersionString"] as? String ?? "不明"
        appBuild = info?["CFBundleVersion"] as? String ?? "不明"
        startingThermalState = startingEnvironment.thermalState
        endingThermalState = endingEnvironment.thermalState
        startingLowPowerModeEnabled =
            startingEnvironment.lowPowerModeEnabled
        endingLowPowerModeEnabled = endingEnvironment.lowPowerModeEnabled
        progressAsset = measurement.progressAsset
        bucketMode = measurement.bucketMode
        rawTranscript = measurement.rawTranscript
    }
}

enum EngineBenchmarkOutputParser {
    static func bestMove(from line: String) -> (move: String, ponder: String?)? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2, tokens[0] == "bestmove" else {
            return nil
        }
        let ponderIndex = tokens.firstIndex(of: "ponder")
        let ponder = ponderIndex.flatMap { index in
            tokens.indices.contains(index + 1) ? tokens[index + 1] : nil
        }
        return (tokens[1], ponder)
    }
}

enum EngineBenchmarkError: LocalizedError {
    case alreadyRunning
    case engineUnavailable(String)
    case incompleteResult(expected: Int, actual: Int)
    case invalidMetrics
    case interrupted

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "別の解析またはベンチマークが実行中です。"
        case let .engineUnavailable(message):
            return message
        case let .incompleteResult(expected, actual):
            return "ベンチマークが完走しませんでした"
                + "（期待局面数\(expected)、完了\(actual)）。"
        case .invalidMetrics:
            return "ベンチマークの探索統計を取得できませんでした。"
        case .interrupted:
            return "ベンチマークを中断しました。"
        }
    }
}

enum EngineBenchmarkStoreError: LocalizedError {
    case unreadable(String)
    case unwritable(String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(reason):
            return "保存済みベンチマークを読み込めませんでした。\(reason)"
        case let .unwritable(reason):
            return "ベンチマーク結果を保存できませんでした。\(reason)"
        }
    }
}

struct EngineBenchmarkStore {
    let fileURL: URL

    init(
        fileURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "EngineBenchmarks/history.json",
            isDirectory: false
        )
    ) {
        self.fileURL = fileURL
    }

    func load() throws -> [EngineBenchmarkRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([EngineBenchmarkRecord].self, from: data)
        } catch {
            throw EngineBenchmarkStoreError.unreadable(
                error.localizedDescription
            )
        }
    }

    func save(_ records: [EngineBenchmarkRecord]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw EngineBenchmarkStoreError.unwritable(
                error.localizedDescription
            )
        }
    }
}

private extension ProcessInfo.ThermalState {
    var benchmarkText: String {
        switch self {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}
