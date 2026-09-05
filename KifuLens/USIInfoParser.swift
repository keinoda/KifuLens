import Foundation

enum EngineScore: Equatable {
    case centipawn(Int)
    case mate(sign: Int, distance: Int?)

    var displayText: String {
        switch self {
        case let .centipawn(value):
            return value >= 0 ? "+\(value)" : "\(value)"
        case let .mate(sign, distance):
            guard let distance, distance > 0 else {
                return "詰み"
            }
            return sign >= 0 ? "+\(distance)手詰" : "-\(distance)手詰"
        }
    }

    func fromBlackPerspective(sideToMoveIsBlack: Bool) -> EngineScore {
        let multiplier = sideToMoveIsBlack ? 1 : -1
        switch self {
        case let .centipawn(value):
            return .centipawn(value * multiplier)
        case let .mate(sign, distance):
            return .mate(sign: sign * multiplier, distance: distance)
        }
    }

    var accessibilityText: String {
        switch self {
        case let .centipawn(value):
            return value >= 0 ? "先手プラス\(value)" : "後手プラス\(abs(value))"
        case let .mate(sign, distance):
            let side = sign >= 0 ? "先手の詰み" : "後手の詰み"
            return distance.map { "\(side)\(abs($0))手" } ?? side
        }
    }
}

struct ParsedUSIInfo: Equatable {
    var depth: Int?
    var seldepth: Int?
    var multipv = 1
    var score: EngineScore?
    var nodes: UInt64?
    var nps: UInt64?
    var timeMilliseconds: Int?
    var hashfull: Int?
    var principalVariation: [String] = []
}

enum USIInfoParser {
    static func parse(_ line: String) -> ParsedUSIInfo? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.first == "info", tokens.count > 1, tokens[1] != "string" else {
            return nil
        }

        var result = ParsedUSIInfo()
        var index = 1
        while index < tokens.count {
            switch tokens[index] {
            case "depth":
                result.depth = integer(after: index, in: tokens)
                index += 2
            case "seldepth":
                result.seldepth = integer(after: index, in: tokens)
                index += 2
            case "multipv":
                result.multipv = max(1, integer(after: index, in: tokens) ?? result.multipv)
                index += 2
            case "nodes":
                result.nodes = unsignedInteger(after: index, in: tokens)
                index += 2
            case "nps":
                result.nps = unsignedInteger(after: index, in: tokens)
                index += 2
            case "time":
                result.timeMilliseconds = integer(after: index, in: tokens)
                index += 2
            case "hashfull":
                result.hashfull = integer(after: index, in: tokens)
                index += 2
            case "score":
                result.score = parseScore(tokens, startingAt: index + 1)
                index += 3
            case "pv":
                result.principalVariation = Array(tokens.dropFirst(index + 1))
                index = tokens.count
            default:
                index += 1
            }
        }
        return result
    }

    private static func parseScore(_ tokens: [String], startingAt index: Int) -> EngineScore? {
        guard index + 1 < tokens.count else {
            return nil
        }
        switch tokens[index] {
        case "cp":
            return Int(tokens[index + 1]).map(EngineScore.centipawn)
        case "mate":
            let raw = tokens[index + 1]
            if raw == "+" {
                return .mate(sign: 1, distance: nil)
            }
            if raw == "-" {
                return .mate(sign: -1, distance: nil)
            }
            guard let distance = Int(raw) else {
                return nil
            }
            return .mate(sign: distance >= 0 ? 1 : -1, distance: abs(distance))
        default:
            return nil
        }
    }

    private static func integer(after index: Int, in tokens: [String]) -> Int? {
        guard index + 1 < tokens.count else {
            return nil
        }
        return Int(tokens[index + 1])
    }

    private static func unsignedInteger(after index: Int, in tokens: [String]) -> UInt64? {
        guard index + 1 < tokens.count else {
            return nil
        }
        return UInt64(tokens[index + 1])
    }
}
