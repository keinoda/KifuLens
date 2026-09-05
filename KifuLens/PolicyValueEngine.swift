import Foundation
import KifuLensEngine

enum PolicyValueState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct PolicyValueMove: Identifiable, Equatable, Sendable {
    let rank: Int
    let usi: String
    let probability: Double
    let logit: Double

    var id: Int { rank }
}

struct PolicyValueResult: Equatable, Sendable {
    let sideToMoveWinRate: Double
    let moves: [PolicyValueMove]
}

protocol PolicyValueAnalyzing: Sendable {
    func analyze(sfen: String, topN: Int) async throws -> PolicyValueResult
}

enum PolicyValueError: LocalizedError {
    case missingModel
    case native(String)

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "DL水匠のpolicy/valueモデルがアプリ内に見つかりません。"
        case let .native(message):
            return message
        }
    }
}

final class NativePolicyValueAnalyzer: PolicyValueAnalyzing, @unchecked Sendable {
    private let bundle: Bundle

    init(bundle: Bundle = .kifuLensApplication) {
        self.bundle = bundle
    }

    func analyze(sfen: String, topN: Int) async throws -> PolicyValueResult {
        guard let modelURL = bundle.url(
            forResource: "DLSuishoPolicyValue",
            withExtension: "mlmodelc"
        ) else {
            throw PolicyValueError.missingModel
        }

        return try await Task.detached(priority: .utility) {
            try Self.runNative(
                sfen: sfen,
                modelPath: modelURL.path,
                topN: topN
            )
        }.value
    }

    private static func runNative(
        sfen: String,
        modelPath: String,
        topN: Int
    ) throws -> PolicyValueResult {
        let capacity = max(1, topN)
        var rawMoves = Array(
            repeating: kifulens_policy_move(),
            count: capacity
        )
        var value: Float = 0
        var errorBuffer = Array<CChar>(repeating: 0, count: 512)

        let count = sfen.withCString { sfenPointer in
            modelPath.withCString { modelPointer in
                rawMoves.withUnsafeMutableBufferPointer { moveBuffer in
                    errorBuffer.withUnsafeMutableBufferPointer { errorPointer in
                        kifulens_policy_value(
                            sfenPointer,
                            modelPointer,
                            Int32(topN),
                            &value,
                            moveBuffer.baseAddress,
                            Int32(capacity),
                            errorPointer.baseAddress,
                            Int32(errorPointer.count)
                        )
                    }
                }
            }
        }

        guard count >= 0 else {
            let message = errorBuffer.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map(String.init(cString:))
            } ?? "DL水匠のpolicy/value推論に失敗しました。"
            throw PolicyValueError.native(message)
        }

        let moves = rawMoves.prefix(Int(count)).enumerated().map { index, raw in
            PolicyValueMove(
                rank: index + 1,
                usi: usiString(raw.usi),
                probability: Double(raw.policy),
                logit: Double(raw.logit)
            )
        }
        return PolicyValueResult(
            sideToMoveWinRate: Double(value),
            moves: moves
        )
    }

    private static func usiString(
        _ tuple: (
            CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar
        )
    ) -> String {
        var value = tuple
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(KIFULENS_POLICY_USI_CAPACITY)
            ) {
                String(cString: $0)
            }
        }
    }
}

@MainActor
final class PolicyValueEngine: ObservableObject {
    // YaneuraOuのMAX_MOVESと同じ上限を確保し、合法手を途中で切らない。
    static let maximumCandidateCount = 600

    @Published private(set) var state: PolicyValueState = .idle
    @Published private(set) var result: PolicyValueResult?

    private let analyzer: any PolicyValueAnalyzing
    private var task: Task<Void, Never>?
    private var requestedSFEN: String?

    init(analyzer: any PolicyValueAnalyzing = NativePolicyValueAnalyzer()) {
        self.analyzer = analyzer
    }

    func analyze(sfen: String) {
        if requestedSFEN == sfen, state == .loading || state == .ready {
            return
        }

        task?.cancel()
        requestedSFEN = sfen
        result = nil
        state = .loading

        task = Task { [weak self, analyzer] in
            do {
                let result = try await analyzer.analyze(
                    sfen: sfen,
                    topN: Self.maximumCandidateCount
                )
                guard !Task.isCancelled,
                      let self,
                      self.requestedSFEN == sfen
                else {
                    return
                }
                self.result = result
                self.state = .ready
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.requestedSFEN == sfen
                else {
                    return
                }
                self.result = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelAndClear() {
        task?.cancel()
        task = nil
        requestedSFEN = nil
        result = nil
        state = .idle
    }
}
