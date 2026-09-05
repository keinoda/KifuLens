import Foundation
import KifuLensEngine

protocol USIProcess: Sendable {
    var assetLoadState: USIAssetLoadState { get }
    func start(
        engineDirectory: String,
        receiveLine: @escaping @Sendable (String) -> Void
    ) -> Bool
    func send(_ line: String)
    func shutdown() async
}

extension USIProcess {
    var assetLoadState: USIAssetLoadState { USIAssetLoadState() }
}

struct USIAssetLoadState: Sendable {
    private(set) var evaluationFilePath: String?
    private(set) var progressFilePath: String?
    private var pendingEvaluationFilePath: String?
    private var pendingProgressFilePath: String?

    mutating func beginSession() {
        pendingEvaluationFilePath = nil
        pendingProgressFilePath = nil
    }

    mutating func observe(_ line: String) {
        let evaluationPrefix = "info string loading eval file : "
        let progressPrefix = "info string loading progress file : "
        if line.hasPrefix(evaluationPrefix) {
            pendingEvaluationFilePath = URL(fileURLWithPath: String(line.dropFirst(evaluationPrefix.count))).standardizedFileURL.path
        } else if line.hasPrefix(progressPrefix) {
            pendingProgressFilePath = URL(fileURLWithPath: String(line.dropFirst(progressPrefix.count))).standardizedFileURL.path
        } else if line == "readyok" {
            // native側の評価資産はUSIスレッド終了後も残る。読込成功を確認したパスだけ保持する。
            evaluationFilePath = pendingEvaluationFilePath ?? evaluationFilePath
            progressFilePath = pendingProgressFilePath ?? progressFilePath
            beginSession()
        }
    }
}

/// 設定で選んだ静的エンジンのCコールバックとUSIの行入出力を接続する。
final class EmbeddedUSIProcess: USIProcess, @unchecked Sendable {
    private static let registryLock = NSLock()
    private static var processes: [AnalysisEngineIdentifier: EmbeddedUSIProcess] = [:]
    static var shared: EmbeddedUSIProcess { forEngine(AnalysisEngineCatalog.defaultEngine.id) }

    static func forEngine(_ identifier: AnalysisEngineIdentifier) -> EmbeddedUSIProcess {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let process = processes[identifier] { return process }
        let process = EmbeddedUSIProcess(identifier: identifier)
        processes[identifier] = process
        return process
    }

    private let identifier: AnalysisEngineIdentifier

    private let inputCondition = NSCondition()
    private var inputBytes = Data()
    private var inputOffset = 0

    private let outputLock = NSLock()
    private var outputBytes = Data()
    private var loadedAssets = USIAssetLoadState()
    private var receiveLine: @Sendable (String) -> Void = { _ in }

    private let lifecycleLock = NSLock()
    private var hasStarted = false
    private var shutdownContinuations: [CheckedContinuation<Void, Never>] = []

    private init(identifier: AnalysisEngineIdentifier) { self.identifier = identifier }

    var assetLoadState: USIAssetLoadState {
        outputLock.lock()
        defer { outputLock.unlock() }
        return loadedAssets
    }

    func start(
        engineDirectory: String,
        receiveLine: @escaping @Sendable (String) -> Void
    ) -> Bool {
        lifecycleLock.lock()
        guard !hasStarted else {
            lifecycleLock.unlock()
            return false
        }
        hasStarted = true
        lifecycleLock.unlock()

        outputLock.lock()
        loadedAssets.beginSession()
        self.receiveLine = receiveLine
        outputLock.unlock()

        let context = Unmanaged.passRetained(self).toOpaque()
        let result = identifier.rawValue.withCString { engineID in
            engineDirectory.withCString { directory in
                kifulens_engine_start(
                    engineID,
                    { context in Unmanaged<EmbeddedUSIProcess>.fromOpaque(context!).takeUnretainedValue().readByte() },
                    { context, byte in Unmanaged<EmbeddedUSIProcess>.fromOpaque(context!).takeUnretainedValue().writeByte(byte) },
                    { context in Unmanaged<EmbeddedUSIProcess>.fromOpaque(context!).takeRetainedValue().didExit() },
                    context,
                    directory
                )
            }
        }
        if result != 0 {
            Unmanaged<EmbeddedUSIProcess>.fromOpaque(context).release()
            lifecycleLock.lock()
            hasStarted = false
            lifecycleLock.unlock()
            return false
        }
        return true
    }

    func send(_ line: String) {
        inputCondition.lock()
        inputBytes.append(contentsOf: (line + "\n").utf8)
        inputCondition.signal()
        inputCondition.unlock()
    }

    func shutdown() async {
        await withCheckedContinuation { continuation in
            lifecycleLock.lock()
            guard hasStarted else {
                lifecycleLock.unlock()
                continuation.resume()
                return
            }
            shutdownContinuations.append(continuation)
            lifecycleLock.unlock()
            send("quit")
        }
    }

    private func didExit() {
        lifecycleLock.lock()
        hasStarted = false
        let continuations = shutdownContinuations
        shutdownContinuations.removeAll()
        lifecycleLock.unlock()

        for continuation in continuations {
            continuation.resume()
        }
    }

    private func readByte() -> Int32 {
        inputCondition.lock()
        while inputOffset >= inputBytes.count {
            inputCondition.wait()
        }
        let byte = inputBytes[inputOffset]
        inputOffset += 1
        if inputOffset == inputBytes.count {
            inputBytes.removeAll(keepingCapacity: true)
            inputOffset = 0
        }
        inputCondition.unlock()
        return Int32(byte)
    }

    private func writeByte(_ value: Int32) {
        guard value >= 0 else {
            return
        }

        var completedLine: String?
        outputLock.lock()
        if value == 0x0A {
            completedLine = String(decoding: outputBytes, as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            outputBytes.removeAll(keepingCapacity: true)
        } else if value != 0x0D {
            outputBytes.append(UInt8(clamping: value))
        }
        if let completedLine {
            loadedAssets.observe(completedLine)
        }
        let callback = receiveLine
        outputLock.unlock()

        if let completedLine, !completedLine.isEmpty {
            callback(completedLine)
        }
    }
}
