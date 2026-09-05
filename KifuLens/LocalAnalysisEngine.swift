import Combine
import Darwin
import Foundation

enum LocalAnalysisConfiguration {
    static let multiPVCount = 3
    static let minimumDeviceAvailableMemoryMB = 256
    static let minimumAvailableMemoryBytes =
        UInt64(minimumDeviceAvailableMemoryMB) * 1_024 * 1_024
}

enum LocalAnalysisCPUCapabilities {
    private static let dotProductBit = 3

    static func supportsDotProductInstructions() -> Bool {
        var byteCount = 0
        guard sysctlbyname(
            "hw.optional.arm.caps",
            nil,
            &byteCount,
            nil,
            0
        ) == 0, byteCount > 0 else {
            return false
        }
        var capabilities = [UInt8](repeating: 0, count: byteCount)
        let status = capabilities.withUnsafeMutableBytes { buffer in
            sysctlbyname(
                "hw.optional.arm.caps",
                buffer.baseAddress,
                &byteCount,
                nil,
                0
            )
        }
        guard status == 0 else {
            return false
        }
        return supportsDotProductInstructions(
            in: Array(capabilities.prefix(byteCount))
        )
    }

    static func supportsDotProductInstructions(in capabilities: [UInt8]) -> Bool {
        let byteIndex = dotProductBit / 8
        let bitMask = UInt8(1 << (dotProductBit % 8))
        guard capabilities.indices.contains(byteIndex) else {
            return false
        }
        return capabilities[byteIndex] & bitMask != 0
    }
}

enum LocalAnalysisState: Equatable {
    case idle
    case starting
    case ready
    case analyzing
    case stopping
    case benchmarking
    case completed
    case failed(String)

    var isBusy: Bool {
        self == .starting
            || self == .analyzing
            || self == .stopping
            || self == .benchmarking
    }

    var isSearching: Bool {
        self == .analyzing || self == .stopping
    }
}

struct EngineAnalysisLine: Identifiable, Equatable {
    let rank: Int
    let score: EngineScore?
    let principalVariation: [String]
    let depth: Int
    let seldepth: Int
    let nodes: UInt64
    let nps: UInt64
    let timeMilliseconds: Int
    let hashfull: Int

    var id: Int { rank }
}

struct EngineSearchMetrics: Equatable {
    var depth = 0
    var seldepth = 0
    var nodes: UInt64 = 0
    var nps: UInt64 = 0
    var timeMilliseconds = 0
    var hashfull = 0
}

struct CompletedEngineSearch: Equatable {
    let requestID: UUID
    let sfen: String
    let sideToMoveIsBlack: Bool
    let engine: AnalysisEngineDescriptor
    let lines: [EngineAnalysisLine]
    let metrics: EngineSearchMetrics
    let stoppedByRequest: Bool
}

enum LocalAnalysisAssetError: LocalizedError {
    case missing(engineName: String, asset: String)
    case unexpectedSize(
        engineName: String,
        asset: String,
        expected: Int64,
        actual: Int64
    )

    var errorDescription: String? {
        switch self {
        case let .missing(engineName, asset):
            return "\(engineName)の\(asset)がアプリ内に見つかりません。"
        case let .unexpectedSize(engineName, asset, expected, actual):
            return "\(engineName)の\(asset)のサイズが一致しません"
                + "（期待値\(expected)、実際\(actual)）。"
        }
    }
}

struct LocalAnalysisAssetSpecification: Equatable, Sendable {
    let directoryName: String
    let nnueSize: Int64
    let progressSize: Int64?
    let bucketMode: String
}

struct LocalAnalysisAssets {
    let nnue: URL
    let progress: URL?

    static func locate(
        specification: LocalAnalysisAssetSpecification,
        engineName: String,
        in bundle: Bundle = .main
    ) throws -> LocalAnalysisAssets {
        let subdirectory = "\(specification.directoryName)/eval"
        let nnue = bundle.url(
            forResource: "nn",
            withExtension: "bin",
            subdirectory: subdirectory
        )
        let progress = specification.progressSize == nil ? nil : bundle.url(
            forResource: "progress",
            withExtension: "bin",
            subdirectory: subdirectory
        )
        guard let nnue else {
            throw LocalAnalysisAssetError.missing(
                engineName: engineName,
                asset: "評価関数 nn.bin"
            )
        }
        try validate(
            nnue,
            engineName: engineName,
            name: "nn.bin",
            expectedSize: specification.nnueSize
        )
        if let expectedSize = specification.progressSize {
            guard let progress else {
                throw LocalAnalysisAssetError.missing(engineName: engineName, asset: "進行度係数 progress.bin")
            }
            try validate(progress, engineName: engineName, name: "progress.bin", expectedSize: expectedSize)
        }
        return LocalAnalysisAssets(nnue: nnue, progress: progress)
    }

    private static func validate(
        _ url: URL,
        engineName: String,
        name: String,
        expectedSize: Int64
    ) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let actualSize = Int64(values.fileSize ?? -1)
        guard actualSize == expectedSize else {
            throw LocalAnalysisAssetError.unexpectedSize(
                engineName: engineName,
                asset: name,
                expected: expectedSize,
                actual: actualSize
            )
        }
    }
}

@MainActor
final class LocalAnalysisEngine: ObservableObject {
    @Published private(set) var state: LocalAnalysisState = .idle
    @Published private(set) var engineName: String
    @Published private(set) var lines: [EngineAnalysisLine] = []
    @Published private(set) var metrics = EngineSearchMetrics()
    @Published private(set) var completionText: String?
    @Published private(set) var loadedEvaluationFilePath: String?
    @Published private(set) var loadedProgressFilePath: String?
    @Published private(set) var completedSearch: CompletedEngineSearch?

    var didLoadEvaluationFile: Bool {
        loadedEvaluationFilePath != nil
    }

    var didLoadProgressFile: Bool {
        loadedProgressFilePath != nil
    }

    var displayName: String {
        descriptor.displayName
    }

    private struct SearchRequest {
        let id: UUID
        let sfen: String
        let sideToMoveIsBlack: Bool
        let configuration: AnalysisSettings
    }

    private enum BenchmarkPhase: Equatable {
        case preparing
        case searching
        case restoring
    }

    private struct BenchmarkPositionAccumulator {
        let position: EngineBenchmarkPosition
        var metrics = EngineSearchMetrics()
        var score: String?
        var principalVariation: [String] = []
    }

    let descriptor: AnalysisEngineDescriptor
    private let process: any USIProcess
    private let assetSpecification: LocalAnalysisAssetSpecification
    private let engineOptions: [EngineUSIOption]
    private let assetBundle: Bundle
    private let supportsDotProductInstructions: () -> Bool
    private let availableMemoryBytes: () -> UInt64
    private var configuration: AnalysisSettings
    private var appliedConfiguration: AnalysisSettings?
    private var preparingConfiguration: AnalysisSettings?
    private var assets: LocalAnalysisAssets?
    private var pendingSearch: SearchRequest?
    private var activeSearch: SearchRequest?
    private var linesByRank: [Int: EngineAnalysisLine] = [:]
    private var interruptedSearch: CompletedEngineSearch?
    private var clearAfterStop = false
    private var responseTimeoutTask: Task<Void, Never>?
    private var pendingBenchmark = false
    private var benchmarkContinuation:
        CheckedContinuation<EngineBenchmarkMeasurement, Error>?
    private var benchmarkPhase: BenchmarkPhase?
    private var benchmarkStartedAt: Date?
    private var benchmarkTranscript: [String] = []
    private var benchmarkResults: [EngineBenchmarkPositionResult] = []
    private var benchmarkPosition: BenchmarkPositionAccumulator?

    init(
        descriptor: AnalysisEngineDescriptor = AnalysisEngineCatalog.defaultEngine,
        configuration: AnalysisSettings = .default,
        process: any USIProcess = EmbeddedUSIProcess.shared,
        assetSpecification: LocalAnalysisAssetSpecification = CompiledEngineConfiguration.defaultEngine.assets,
        engineOptions: [EngineUSIOption] = CompiledEngineConfiguration.defaultEngine.options,
        assetBundle: Bundle = .main,
        supportsDotProductInstructions: @escaping () -> Bool = {
            LocalAnalysisCPUCapabilities.supportsDotProductInstructions()
        },
        availableMemoryBytes: @escaping () -> UInt64 = {
#if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-ui-test-local-analysis-memory") {
                return 1_024 * 1_024 * 1_024
            }
#endif
            return UInt64(os_proc_available_memory())
        }
    ) {
        self.descriptor = descriptor
        self.configuration = configuration
        self.process = process
        self.assetSpecification = assetSpecification
        self.engineOptions = engineOptions
        self.assetBundle = assetBundle
        self.supportsDotProductInstructions = supportsDotProductInstructions
        self.availableMemoryBytes = availableMemoryBytes
        engineName = descriptor.displayName
    }

    func updateConfiguration(_ configuration: AnalysisSettings) {
        self.configuration = configuration
    }

    func runBenchmark() async throws -> EngineBenchmarkMeasurement {
        guard benchmarkContinuation == nil, !state.isBusy else {
            throw EngineBenchmarkError.alreadyRunning
        }
        if case let .failed(message) = state {
            throw EngineBenchmarkError.engineUnavailable(message)
        }

        return try await withCheckedThrowingContinuation { continuation in
            benchmarkContinuation = continuation
            pendingBenchmark = true
            benchmarkStartedAt = Date()
            benchmarkTranscript = []
            benchmarkResults = []
            benchmarkPosition = nil
            benchmarkPhase = nil
            completionText = nil
            completedSearch = nil
            clearPublishedResults()

            switch state {
            case .idle:
                startEngine()
            case .ready, .completed:
                pendingBenchmark = false
                prepareBenchmark()
            default:
                failBenchmark(EngineBenchmarkError.alreadyRunning)
            }
        }
    }

    func shutdown() async {
        guard !state.isBusy else {
            return
        }
        await process.shutdown()
        state = .idle
        assets = nil
        appliedConfiguration = nil
        preparingConfiguration = nil
        loadedEvaluationFilePath = nil
        loadedProgressFilePath = nil
        clearPublishedResults()
    }

    @discardableResult
    func analyze(sfen: String, sideToMoveIsBlack: Bool) -> UUID {
        let request = SearchRequest(
            id: UUID(),
            sfen: sfen,
            sideToMoveIsBlack: sideToMoveIsBlack,
            configuration: configuration
        )
        completionText = nil
        completedSearch = nil

        switch state {
        case .idle:
            clearPublishedResults()
            pendingSearch = request
            startEngine()
        case .starting:
            clearPublishedResults()
            pendingSearch = request
        case .ready, .completed:
            prepareOrBegin(request)
        case .analyzing:
            interruptedSearch = completion(
                for: activeSearch,
                stoppedByRequest: true
            )
            clearPublishedResults()
            pendingSearch = request
            requestStop(clearResultsAfterStop: false)
        case .stopping:
            clearPublishedResults()
            pendingSearch = request
            clearAfterStop = false
        case .benchmarking:
            break
        case .failed:
            break
        }
        return request.id
    }

    func stop() {
        guard state == .analyzing else {
            return
        }
        pendingSearch = nil
        requestStop(clearResultsAfterStop: false)
    }

    func cancelAndClear() {
        pendingSearch = nil
        interruptedSearch = nil
        completionText = nil
        clearPublishedResults()

        switch state {
        case .analyzing:
            requestStop(clearResultsAfterStop: true)
        case .stopping:
            clearAfterStop = true
        case .completed:
            state = .ready
        default:
            break
        }
    }

    func pauseForBackground() {
        pendingSearch = nil
        if state == .analyzing {
            requestStop(clearResultsAfterStop: false)
        } else if state == .benchmarking {
            failBenchmark(EngineBenchmarkError.interrupted)
        }
    }

    private func startEngine() {
        state = .starting
        loadedEvaluationFilePath = nil
        loadedProgressFilePath = nil
        guard configuration.engineIdentifier == descriptor.id else {
            fail("選択した端末内エンジンを利用できません。")
            return
        }
        guard supportsDotProductInstructions() else {
            fail(
                "この端末のCPUは\(descriptor.displayName)に必要な"
                    + "DotProd命令に対応していません。"
            )
            return
        }
        let requiredMemoryMB = max(
            LocalAnalysisConfiguration.minimumDeviceAvailableMemoryMB,
            configuration.hashSizeMB
        )
        guard availableMemoryBytes()
            >= UInt64(requiredMemoryMB) * 1_024 * 1_024
        else {
            fail(
                "端末内解析には\(requiredMemoryMB) MB以上の利用可能メモリが必要です。"
                    + "ほかのアプリを終了してから再度お試しください。"
            )
            return
        }
        do {
            let locatedAssets = try LocalAnalysisAssets.locate(
                specification: assetSpecification,
                engineName: descriptor.displayName,
                in: assetBundle
            )
            assets = locatedAssets
            let directory = locatedAssets.nnue.deletingLastPathComponent().path
            let didStart = process.start(
                engineDirectory: directory
            ) { [weak self] line in
                DispatchQueue.main.async {
                    self?.receive(line)
                }
            }
            guard didStart else {
                fail(
                    "\(descriptor.displayName)の端末内エンジンスレッドを"
                        + "開始できませんでした。"
                )
                return
            }
            process.send("usi")
            armResponseTimeout(
                expectedState: .starting,
                seconds: 60,
                message: "\(descriptor.displayName)からusiokが"
                    + "60秒以内に返りませんでした。"
            )
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func receive(_ line: String) {
        if case .failed = state { return }
        if benchmarkContinuation != nil {
            benchmarkTranscript.append(line)
        }
        if state == .benchmarking {
            receiveBenchmark(line)
            return
        }
        if line.hasPrefix("id name ") {
            engineName = String(line.dropFirst("id name ".count))
            return
        }
        if line == "usiok" {
            configureAndPrepare(configuration)
            return
        }
        if line == "readyok" {
            let confirmed = process.assetLoadState
            loadedEvaluationFilePath = loadedEvaluationFilePath ?? confirmed.evaluationFilePath
            loadedProgressFilePath = loadedProgressFilePath ?? confirmed.progressFilePath
            guard let assets else {
                fail("\(descriptor.displayName)の評価資産を解決できませんでした。")
                return
            }
            guard loadedEvaluationFilePath
                == assets.nnue.standardizedFileURL.path
            else {
                fail(
                    "\(descriptor.displayName)の評価関数 nn.bin を"
                        + "指定パスから読み込めませんでした。"
                )
                return
            }
            if let progress = assets.progress,
               loadedProgressFilePath != progress.standardizedFileURL.path {
                fail(
                    "\(descriptor.displayName)の進行度係数 progress.bin を"
                        + "指定パスから読み込めませんでした。"
                )
                return
            }
            cancelResponseTimeout()
            appliedConfiguration = preparingConfiguration
            preparingConfiguration = nil
            process.send("usinewgame")
            state = .ready
            if pendingBenchmark {
                pendingBenchmark = false
                prepareBenchmark()
                return
            }
            if let pendingSearch {
                self.pendingSearch = nil
                prepareOrBegin(pendingSearch)
            }
            return
        }
        let evaluationPrefix = "info string loading eval file : "
        if line.hasPrefix(evaluationPrefix) {
            loadedEvaluationFilePath = URL(
                fileURLWithPath: String(line.dropFirst(evaluationPrefix.count))
            ).standardizedFileURL.path
            return
        }
        let progressPrefix = "info string loading progress file : "
        if line.hasPrefix(progressPrefix) {
            loadedProgressFilePath = URL(
                fileURLWithPath: String(line.dropFirst(progressPrefix.count))
            ).standardizedFileURL.path
            return
        }
        if line.hasPrefix("info string Error") || line.hasPrefix("Error") || line.hasPrefix("No such option:") {
            fail(line)
            return
        }
        if line.hasPrefix("bestmove") {
            if case .failed = state {
                return
            }
            finishSearch()
            return
        }
        let acceptsInfo = state == .analyzing
            || (
                state == .stopping
                    && pendingSearch == nil
                    && !clearAfterStop
            )
        guard acceptsInfo,
              let parsed = USIInfoParser.parse(line),
              let activeSearch
        else {
            return
        }
        update(parsed, sideToMoveIsBlack: activeSearch.sideToMoveIsBlack)
    }

    private func configureAndPrepare(_ configuration: AnalysisSettings) {
        guard let assets else {
            fail("\(descriptor.displayName)の評価資産を解決できませんでした。")
            return
        }

        preparingConfiguration = configuration
        let evalDirectory = assets.nnue.deletingLastPathComponent().path
        var options = [
            ("Threads", "\(configuration.threadCount)"),
            ("USI_Hash", "\(configuration.hashSizeMB)"),
            ("MultiPV", "\(LocalAnalysisConfiguration.multiPVCount)"),
            ("USI_Ponder", "false"),
            ("ConsiderationMode", "true"),
            ("MaxMovesToDraw", "512"),
            ("USI_OwnBook", "false"),
            ("BookFile", "no_book"),
            ("EvalDir", evalDirectory),
        ]
        for option in engineOptions {
            let value: String
            if option.value == "@progress" {
                guard let progress = assets.progress else {
                    fail("\(descriptor.displayName)の設定が必要とするprogress.binが見つかりません。")
                    return
                }
                value = progress.path
            } else {
                value = option.value
            }
            options.append((option.name, value))
        }
        for (name, value) in options {
            process.send("setoption name \(name) value \(value)")
        }
        process.send("isready")
        armResponseTimeout(
            expectedState: .starting,
            seconds: 60,
            message: "\(descriptor.displayName)の評価関数準備が"
                + "60秒以内に完了しませんでした。"
        )
    }

    private func prepareBenchmark() {
        state = .benchmarking
        benchmarkPhase = .preparing
        process.send("setoption name MultiPV value 1")
        process.send("isready")
        armResponseTimeout(
            expectedState: .benchmarking,
            seconds: 60,
            message: "\(descriptor.displayName)のベンチマークを準備できませんでした。"
        )
    }

    private func receiveBenchmark(_ line: String) {
        if line.hasPrefix("info string Error") || line.hasPrefix("Error") || line.hasPrefix("No such option:") {
            failBenchmark(EngineBenchmarkError.engineUnavailable(line))
            return
        }

        switch benchmarkPhase {
        case .preparing:
            guard line == "readyok" else {
                return
            }
            prepareNextBenchmarkPosition()
            process.send(
                EngineBenchmarkConfiguration.command(for: configuration)
            )
            armResponseTimeout(
                expectedState: .benchmarking,
                seconds: 180,
                message: "\(descriptor.displayName)のベンチマークが"
                    + "180秒以内に応答しませんでした。"
            )
        case .searching:
            if let parsed = USIInfoParser.parse(line) {
                updateBenchmarkPosition(with: parsed)
                return
            }
            guard line.hasPrefix("bestmove") else {
                return
            }
            guard let bestMove = EngineBenchmarkOutputParser.bestMove(
                from: line
            ) else {
                failBenchmark(EngineBenchmarkError.invalidMetrics)
                return
            }
            completeBenchmarkPosition(with: bestMove)
        case .restoring:
            guard line == "readyok" else {
                return
            }
            finishBenchmark()
        case nil:
            break
        }
    }

    private func prepareNextBenchmarkPosition() {
        let index = benchmarkResults.count
        guard EngineBenchmarkConfiguration.positions.indices.contains(index)
        else {
            restoreConfigurationAfterBenchmark()
            return
        }

        let position = EngineBenchmarkConfiguration.positions[index]
        benchmarkPosition = BenchmarkPositionAccumulator(position: position)
        benchmarkPhase = .searching
    }

    private func updateBenchmarkPosition(with parsed: ParsedUSIInfo) {
        guard var accumulator = benchmarkPosition else {
            return
        }
        if let depth = parsed.depth {
            accumulator.metrics.depth = max(
                accumulator.metrics.depth,
                depth
            )
        }
        if let seldepth = parsed.seldepth {
            accumulator.metrics.seldepth = max(
                accumulator.metrics.seldepth,
                seldepth
            )
        }
        if let nodes = parsed.nodes {
            accumulator.metrics.nodes = nodes
        }
        if let nps = parsed.nps {
            accumulator.metrics.nps = nps
        }
        if let timeMilliseconds = parsed.timeMilliseconds {
            accumulator.metrics.timeMilliseconds = timeMilliseconds
        }
        if let hashfull = parsed.hashfull {
            accumulator.metrics.hashfull = max(
                accumulator.metrics.hashfull,
                hashfull
            )
        }
        if let score = parsed.score {
            accumulator.score = score.displayText
        }
        if !parsed.principalVariation.isEmpty {
            accumulator.principalVariation = parsed.principalVariation
        }
        benchmarkPosition = accumulator
    }

    private func completeBenchmarkPosition(
        with bestMove: (move: String, ponder: String?)
    ) {
        guard let accumulator = benchmarkPosition else {
            failBenchmark(EngineBenchmarkError.invalidMetrics)
            return
        }
        let metrics = accumulator.metrics
        benchmarkResults.append(
            EngineBenchmarkPositionResult(
                index: accumulator.position.index,
                sfen: accumulator.position.sfen,
                depth: metrics.depth,
                seldepth: metrics.seldepth,
                nodes: metrics.nodes,
                nps: metrics.nps,
                timeMilliseconds: metrics.timeMilliseconds,
                hashfull: metrics.hashfull,
                score: accumulator.score,
                principalVariation: accumulator.principalVariation,
                bestmove: bestMove.move,
                ponder: bestMove.ponder
            )
        )
        benchmarkPosition = nil
        prepareNextBenchmarkPosition()
    }

    private func restoreConfigurationAfterBenchmark() {
        benchmarkPhase = .restoring
        process.send(
            "setoption name MultiPV value "
                + "\(LocalAnalysisConfiguration.multiPVCount)"
        )
        process.send("isready")
        armResponseTimeout(
            expectedState: .benchmarking,
            seconds: 60,
            message: "\(descriptor.displayName)の解析設定を"
                + "ベンチマーク後に復元できませんでした。"
        )
    }

    private func finishBenchmark() {
        guard benchmarkResults.count
            == EngineBenchmarkConfiguration.positions.count
        else {
            failBenchmark(
                EngineBenchmarkError.incompleteResult(
                    expected: EngineBenchmarkConfiguration.positions.count,
                    actual: benchmarkResults.count
                )
            )
            return
        }
        let totalTime = benchmarkResults.reduce(0) {
            $0 + $1.timeMilliseconds
        }
        let totalNodes = benchmarkResults.reduce(UInt64(0)) {
            $0 + $1.nodes
        }
        guard totalTime > 0, totalNodes > 0,
              let startedAt = benchmarkStartedAt,
              let continuation = benchmarkContinuation
        else {
            failBenchmark(EngineBenchmarkError.invalidMetrics)
            return
        }

        let measurement = EngineBenchmarkMeasurement(
            startedAt: startedAt,
            finishedAt: Date(),
            engine: descriptor,
            configuration: configuration,
            command: EngineBenchmarkConfiguration.command(
                for: configuration
            ),
            buildVariant: EngineBenchmarkConfiguration.buildVariant,
            depthLimit: nil,
            totalTimeMilliseconds: totalTime,
            totalNodes: totalNodes,
            nodesPerSecond: totalNodes * 1_000 / UInt64(totalTime),
            positions: benchmarkResults,
            rawTranscript: benchmarkTranscript,
            progressAsset: assetSpecification.progressSize == nil
                ? "なし" : "\(assetSpecification.directoryName)/eval/progress.bin",
            bucketMode: assetSpecification.bucketMode
        )

        cancelResponseTimeout()
        benchmarkContinuation = nil
        pendingBenchmark = false
        benchmarkPhase = nil
        benchmarkStartedAt = nil
        benchmarkPosition = nil
        benchmarkResults = []
        benchmarkTranscript = []
        state = .ready
        clearPublishedResults()
        continuation.resume(returning: measurement)
    }

    private func failBenchmark(_ error: Error) {
        let shouldStop = state == .benchmarking
            && benchmarkPhase == .searching
        let continuation = benchmarkContinuation
        cancelResponseTimeout()
        benchmarkContinuation = nil
        pendingBenchmark = false
        benchmarkPhase = nil
        benchmarkStartedAt = nil
        benchmarkPosition = nil
        benchmarkResults = []
        benchmarkTranscript = []
        completionText = nil
        state = .failed(error.localizedDescription)
        if shouldStop {
            process.send("stop")
        }
        continuation?.resume(throwing: error)
    }

    private func prepareOrBegin(_ request: SearchRequest) {
        guard request.configuration.engineIdentifier == descriptor.id else {
            fail("選択した端末内エンジンを利用できません。")
            return
        }
        if requiresUSIReconfiguration(for: request.configuration) {
            pendingSearch = request
            state = .starting
            configureAndPrepare(request.configuration)
            return
        }
        begin(request)
    }

    private func requiresUSIReconfiguration(
        for configuration: AnalysisSettings
    ) -> Bool {
        guard let appliedConfiguration else {
            return true
        }
        return appliedConfiguration.threadCount != configuration.threadCount
            || appliedConfiguration.hashSizeMB != configuration.hashSizeMB
    }

    private func begin(_ request: SearchRequest) {
        activeSearch = request
        interruptedSearch = nil
        pendingSearch = nil
        clearAfterStop = false
        completionText = nil
        clearPublishedResults()
        process.send("position sfen \(request.sfen)")
        process.send(request.configuration.timeLimit.goCommand)
        state = .analyzing
    }

    private func update(_ parsed: ParsedUSIInfo, sideToMoveIsBlack: Bool) {
        var nextMetrics = metrics
        if let depth = parsed.depth {
            nextMetrics.depth = depth
        }
        if let seldepth = parsed.seldepth {
            nextMetrics.seldepth = seldepth
        }
        if let nodes = parsed.nodes {
            nextMetrics.nodes = nodes
        }
        if let nps = parsed.nps {
            nextMetrics.nps = nps
        }
        if let timeMilliseconds = parsed.timeMilliseconds {
            nextMetrics.timeMilliseconds = timeMilliseconds
        }
        if let hashfull = parsed.hashfull {
            nextMetrics.hashfull = hashfull
        }
        metrics = nextMetrics

        guard !parsed.principalVariation.isEmpty else {
            return
        }
        let line = EngineAnalysisLine(
            rank: parsed.multipv,
            score: parsed.score?.fromBlackPerspective(
                sideToMoveIsBlack: sideToMoveIsBlack
            ),
            principalVariation: parsed.principalVariation,
            depth: nextMetrics.depth,
            seldepth: nextMetrics.seldepth,
            nodes: nextMetrics.nodes,
            nps: nextMetrics.nps,
            timeMilliseconds: nextMetrics.timeMilliseconds,
            hashfull: nextMetrics.hashfull
        )
        linesByRank[line.rank] = line
        lines = linesByRank.values.sorted { $0.rank < $1.rank }
    }

    private func finishSearch() {
        let stoppedByRequest = state == .stopping
        let timeLimit = activeSearch?.configuration.timeLimit
            ?? configuration.timeLimit
        cancelResponseTimeout()
        let finishedSearch = interruptedSearch
            ?? completion(
                for: activeSearch,
                stoppedByRequest: stoppedByRequest
            )
        activeSearch = nil
        interruptedSearch = nil
        if !clearAfterStop, let finishedSearch {
            completedSearch = finishedSearch
        }
        if let pendingSearch {
            self.pendingSearch = nil
            prepareOrBegin(pendingSearch)
            return
        }

        if clearAfterStop {
            clearAfterStop = false
            clearPublishedResults()
            state = .ready
        } else {
            completionText = stoppedByRequest
                ? "解析停止"
                : "\(timeLimit.displayText)解析完了"
            state = .completed
        }
    }

    private func completion(
        for request: SearchRequest?,
        stoppedByRequest: Bool
    ) -> CompletedEngineSearch? {
        guard let request else {
            return nil
        }
        let completedLines = linesByRank.values.sorted { $0.rank < $1.rank }
        guard !completedLines.isEmpty else {
            return nil
        }
        return CompletedEngineSearch(
            requestID: request.id,
            sfen: request.sfen,
            sideToMoveIsBlack: request.sideToMoveIsBlack,
            engine: descriptor,
            lines: completedLines,
            metrics: metrics,
            stoppedByRequest: stoppedByRequest
        )
    }

    private func clearPublishedResults() {
        linesByRank = [:]
        lines = []
        metrics = EngineSearchMetrics()
    }

    private func fail(_ message: String) {
        if benchmarkContinuation != nil {
            failBenchmark(EngineBenchmarkError.engineUnavailable(message))
            return
        }
        let shouldStop = state == .analyzing || state == .stopping
        cancelResponseTimeout()
        pendingSearch = nil
        activeSearch = nil
        interruptedSearch = nil
        completionText = nil
        state = .failed(message)
        if shouldStop {
            process.send("stop")
        }
    }

    private func requestStop(clearResultsAfterStop: Bool) {
        clearAfterStop = clearResultsAfterStop
        state = .stopping
        process.send("stop")
        armResponseTimeout(
            expectedState: .stopping,
            seconds: 5,
            message: "\(descriptor.displayName)がstopへ"
                + "5秒以内に応答しませんでした。"
        )
    }

    private func armResponseTimeout(
        expectedState: LocalAnalysisState,
        seconds: UInt64,
        message: String
    ) {
        cancelResponseTimeout()
        responseTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            } catch {
                return
            }
            guard let self, self.state == expectedState else {
                return
            }
            self.fail(message)
        }
    }

    private func cancelResponseTimeout() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
    }
}
