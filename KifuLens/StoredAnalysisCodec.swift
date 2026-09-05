import Foundation

struct StoredAnalysisLine: Identifiable, Equatable {
    let rank: Int
    let depth: Int
    let seldepth: Int
    let nodes: UInt64
    let score: EngineScore?
    let reading: [String]

    var id: Int { rank }
}

struct StoredAnalysis: Equatable {
    let engineName: String
    let version: String
    let lines: [StoredAnalysisLine]
}

enum StoredAnalysisCodec {
    static let nagisaEngineName = "NAGISA"
    static let nagisaVersion = "v3.1"

    private static let expression = try! NSRegularExpression(
        pattern:
            #"^\* Engine (.+?) Version (.+?) 候補([0-9]+) 深さ ([0-9]+)/([0-9]+) ノード数 ([0-9]+) 評価値 (\S+) 読み筋 (.+)$"#
    )
    private static let readingExpression = try! NSRegularExpression(
        pattern: #"[▲△☗☖][^▲△☗☖]+"#
    )

    static func analyses(in comment: String) -> [StoredAnalysis] {
        var order: [(String, String)] = []
        var grouped: [String: [StoredAnalysisLine]] = [:]

        for line in comment.components(separatedBy: .newlines) {
            guard let parsed = parse(line) else {
                continue
            }
            let key = "\(parsed.engineName)\u{0}\(parsed.version)"
            if grouped[key] == nil {
                order.append((parsed.engineName, parsed.version))
            }
            grouped[key, default: []].append(parsed.line)
        }

        return order.compactMap { engineName, version in
            let key = "\(engineName)\u{0}\(version)"
            guard let lines = grouped[key], !lines.isEmpty else {
                return nil
            }
            return StoredAnalysis(
                engineName: engineName,
                version: version,
                lines: lines.sorted { $0.rank < $1.rank }
            )
        }
    }

    static func replacingNagisaLines(
        in comment: String,
        with lines: [StoredAnalysisLine]
    ) -> String {
        replacingEngineLines(
            in: comment,
            engineName: nagisaEngineName,
            version: nagisaVersion,
            with: lines
        )
    }

    static func replacingEngineLines(
        in comment: String,
        engineName: String,
        version: String,
        with lines: [StoredAnalysisLine]
    ) -> String {
        let prefix = "* Engine \(engineName) Version \(version) 候補"
        var existing = comment.components(separatedBy: .newlines)
        if existing.last?.isEmpty == true {
            existing.removeLast()
        }
        existing.removeAll { $0.hasPrefix(prefix) }

        let formatted = lines
            .sorted { $0.rank < $1.rank }
            .map {
                format(
                    engineName: engineName,
                    version: version,
                    line: $0
                )
            }
        let combined = existing + formatted
        return combined.isEmpty ? "" : combined.joined(separator: "\n") + "\n"
    }

    private static func parse(
        _ line: String
    ) -> (engineName: String, version: String, line: StoredAnalysisLine)? {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              match.numberOfRanges == 9,
              let engineName = capture(1, match: match, in: line),
              let version = capture(2, match: match, in: line),
              let rankText = capture(3, match: match, in: line),
              let depthText = capture(4, match: match, in: line),
              let seldepthText = capture(5, match: match, in: line),
              let nodesText = capture(6, match: match, in: line),
              let scoreText = capture(7, match: match, in: line),
              let readingText = capture(8, match: match, in: line),
              let rank = Int(rankText),
              let depth = Int(depthText),
              let seldepth = Int(seldepthText),
              let nodes = UInt64(nodesText)
        else {
            return nil
        }

        let reading = readingTokens(in: readingText)
        guard !reading.isEmpty else {
            return nil
        }
        return (
            engineName,
            version,
            StoredAnalysisLine(
                rank: rank,
                depth: depth,
                seldepth: seldepth,
                nodes: nodes,
                score: parseScore(scoreText),
                reading: reading
            )
        )
    }

    private static func format(
        engineName: String,
        version: String,
        line: StoredAnalysisLine
    ) -> String {
        let scoreText: String
        switch line.score {
        case let .centipawn(value):
            scoreText = "\(value)"
        case let .mate(sign, distance):
            if let distance {
                scoreText = sign >= 0 ? "+\(distance)手詰" : "-\(distance)手詰"
            } else {
                scoreText = "詰み"
            }
        case nil:
            scoreText = "0"
        }
        return "* Engine \(engineName) Version \(version) "
            + "候補\(line.rank) 深さ \(line.depth)/\(line.seldepth) "
            + "ノード数 \(line.nodes) 評価値 \(scoreText) "
            + "読み筋 \(line.reading.joined(separator: " "))"
    }

    private static func parseScore(_ text: String) -> EngineScore? {
        if let value = Int(text) {
            return .centipawn(value)
        }
        if text == "詰み" {
            return .mate(sign: 1, distance: nil)
        }
        let suffix = "手詰"
        guard text.hasSuffix(suffix),
              let distance = Int(text.dropLast(suffix.count))
        else {
            return nil
        }
        return .mate(
            sign: distance >= 0 ? 1 : -1,
            distance: abs(distance)
        )
    }

    private static func readingTokens(in text: String) -> [String] {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return readingExpression.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map {
                text[$0].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private static func capture(
        _ index: Int,
        match: NSTextCheckingResult,
        in text: String
    ) -> String? {
        Range(match.range(at: index), in: text).map {
            String(text[$0])
        }
    }
}
