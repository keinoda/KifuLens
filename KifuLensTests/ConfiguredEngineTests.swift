import Foundation
import SwiftShogi
import XCTest
@testable import KifuLens

private final class EngineLines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ line: String) { lock.lock(); defer { lock.unlock() }; storage.append(line) }
}

private struct SearchFingerprint: Equatable {
    let depth: Int?
    let seldepth: Int?
    let score: EngineScore?
    let pv: [String]
    let bestmove: String
}

final class ConfiguredEngineTests: XCTestCase {
    @MainActor
    func testEveryConfiguredEngineSearchesAndRestartsWithoutChangingPolicy() async throws {
        let entries = CompiledEngineConfiguration.engines
        XCTAssertFalse(entries.isEmpty)
        let sfen = Position().sfen
        var policyBaseline: PolicyValueResult?
        var searchBaselines: [AnalysisEngineIdentifier: SearchFingerprint] = [:]

        // 一周後に同じエンジンへ戻り、他のエンジンの状態が混ざっていないことを確認する。
        for entry in entries + entries {
            let descriptor = entry.descriptor
            let assets = try LocalAnalysisAssets.locate(specification: entry.assets, engineName: descriptor.displayName)
            let process = EmbeddedUSIProcess.forEngine(descriptor.id)
            let policy = try await NativePolicyValueAnalyzer().analyze(sfen: sfen, topN: PolicyValueEngine.maximumCandidateCount)
            XCTAssertEqual(policy.moves.count, 30)
            XCTAssertTrue(policy.moves.allSatisfy { $0.probability.isFinite && (0...1).contains($0.probability) })
            XCTAssertEqual(policy.moves.reduce(0) { $0 + $1.probability }, 1, accuracy: 0.0001)
            if let policyBaseline { XCTAssertEqual(policy, policyBaseline) } else { policyBaseline = policy }
            let output = EngineLines()
            guard process.start(engineDirectory: assets.nnue.deletingLastPathComponent().path, receiveLine: { output.append($0) }) else {
                XCTFail("\(descriptor.displayName)を開始できません"); return
            }
            do {
                process.send("usi")
                try await waitFor(output) { $0.contains("usiok") }
                let common = [("Threads", "1"), ("USI_Hash", "256"), ("MultiPV", "3"),
                              ("USI_OwnBook", "false"), ("BookFile", "no_book"), ("MaxMovesToDraw", "512"),
                              ("EvalDir", assets.nnue.deletingLastPathComponent().path)]
                for (name, value) in common { process.send("setoption name \(name) value \(value)") }
                for option in entry.options {
                    let value = option.value == "@progress" ? try XCTUnwrap(assets.progress).path : option.value
                    process.send("setoption name \(option.name) value \(value)")
                }
                process.send("isready")
                try await waitFor(output) { $0.contains("readyok") }
                XCTAssertEqual(process.assetLoadState.evaluationFilePath, assets.nnue.standardizedFileURL.path)
                if let progress = assets.progress {
                    XCTAssertEqual(process.assetLoadState.progressFilePath, progress.standardizedFileURL.path)
                }
                process.send("position startpos")
                process.send("go nodes 100000")
                try await waitFor(output) { $0.contains { $0.hasPrefix("bestmove ") } }
                let line = try XCTUnwrap(output.lines.last { $0.hasPrefix("info depth ") && $0.contains(" multipv 1 ") })
                let info = try XCTUnwrap(USIInfoParser.parse(line))
                // 初期局面で4手程度の偽の千日手に終わる、今回再現した失敗を検出する。
                XCTAssertGreaterThan(try XCTUnwrap(info.seldepth), 6, line)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(info.nodes), 100_000, line)
                let fingerprint = SearchFingerprint(depth: info.depth, seldepth: info.seldepth, score: info.score,
                    pv: info.principalVariation, bestmove: try XCTUnwrap(output.lines.last { $0.hasPrefix("bestmove ") }))
                if let previous = searchBaselines[descriptor.id] {
                    XCTAssertEqual(fingerprint, previous)
                } else {
                    searchBaselines[descriptor.id] = fingerprint
                }
                let after = try await NativePolicyValueAnalyzer().analyze(sfen: sfen, topN: PolicyValueEngine.maximumCandidateCount)
                XCTAssertEqual(after, policy)
                XCTAssertFalse(output.lines.contains { $0.hasPrefix("Error") || $0.lowercased().contains("no such option") })
                let attachment = XCTAttachment(string: output.lines.joined(separator: "\n"))
                attachment.name = "設定エンジン-\(descriptor.id.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch {
                await process.shutdown()
                throw error
            }
            await process.shutdown()
        }
    }

    @MainActor
    private func waitFor(_ output: EngineLines, condition: ([String]) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        while !condition(output.lines) {
            if Date() >= deadline {
                throw NSError(domain: "ConfiguredEngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "USI応答を確認できません。\n\(output.lines.suffix(8).joined(separator: "\n"))"])
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
