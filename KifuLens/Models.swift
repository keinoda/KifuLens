import Foundation
import SwiftShogi

enum DetailPanel: String, CaseIterable, Hashable, Identifiable {
    case settings = "設定"
    case record = "棋譜"
    case analysis = "解析"
    case book = "定跡"
    case precedent = "前例"

    var id: String { rawValue }
}

enum BoardSelection: Equatable {
    case board(Square)
    case hand(PieceType)
}

struct PendingPromotion: Identifiable {
    let id = UUID()
    let plain: Move
    let promoted: Move
}

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct OpeningBookSummary: Equatable {
    let fileName: String
    let fileSize: Int64
    let positionCount: Int?
    let moveCount: Int?
    let isFastEstimate: Bool

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum PrecedentLookupState: Equatable {
    case idle
    case opening
    case lookingUp
    case loaded
    case failed(String)
}

struct PrecedentMove: Identifiable, Equatable {
    var id: String { usi }

    var unknownCount: Int {
        max(0, count - blackWinCount - whiteWinCount - drawCount)
    }

    let usi: String
    let displayText: String
    let count: Int
    let blackWinCount: Int
    let whiteWinCount: Int
    let drawCount: Int
}

enum PrecedentOutcome: String, Equatable {
    case blackWin
    case whiteWin
    case draw
    case unknown

    var title: String {
        switch self {
        case .blackWin:
            return "先手勝ち"
        case .whiteWin:
            return "後手勝ち"
        case .draw:
            return "引分"
        case .unknown:
            return "不明"
        }
    }
}

struct PrecedentExample: Identifiable, Equatable {
    let id: String
    let gameID: UUID
    let fileName: String
    let ply: Int
    let blackName: String
    let whiteName: String
    let dateText: String
    let nextMoveUSI: String
    let nextMoveText: String
    let outcome: PrecedentOutcome
}

struct PrecedentSummary: Equatable {
    let occurrenceCount: Int
    let moves: [PrecedentMove]
    let examples: [PrecedentExample]

    static let empty = PrecedentSummary(
        occurrenceCount: 0,
        moves: [],
        examples: []
    )
}
