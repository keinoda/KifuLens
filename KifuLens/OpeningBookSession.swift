import Foundation
import SwiftShogi

enum OpeningBookSessionError: LocalizedError {
    case unsupportedExtension(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(value):
            return "定跡形式「\(value)」には対応していません。.dbまたは.ybbを選んでください。"
        }
    }
}

final class OpeningBookSession: @unchecked Sendable {
    private enum Storage {
        case text(YaneuraOuDBReader)
        case binary(YaneuraOuBinaryBookReader)
    }

    private let storage: Storage
    let summary: OpeningBookSummary

    private init(storage: Storage, summary: OpeningBookSummary) {
        self.storage = storage
        self.summary = summary
    }

    static func open(
        url: URL,
        displayName: String? = nil
    ) throws -> OpeningBookSession {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let scopedURL = didStartAccess ? url : nil
        let fileName = url.lastPathComponent
        let summaryName = displayName ?? fileName

        do {
            switch url.pathExtension.lowercased() {
            case "db":
                let reader = try YaneuraOuDBReader.open(
                    url: url,
                    sourceFileName: fileName,
                    fastOpen: true,
                    securityScopedURL: scopedURL
                )
                let stats = reader.statistics
                return OpeningBookSession(
                    storage: .text(reader),
                    summary: OpeningBookSummary(
                        fileName: summaryName,
                        fileSize: stats.fileSize,
                        positionCount: stats.positionCount,
                        moveCount: stats.moveCount,
                        isFastEstimate: !stats.isComplete
                    )
                )

            case "ybb":
                let reader = try YaneuraOuBinaryBookReader.open(
                    url: url,
                    sourceFileName: fileName,
                    fastOpen: true,
                    securityScopedURL: scopedURL
                )
                let stats = reader.statistics
                return OpeningBookSession(
                    storage: .binary(reader),
                    summary: OpeningBookSummary(
                        fileName: summaryName,
                        fileSize: stats.fileSize,
                        positionCount: stats.positionCount,
                        moveCount: stats.moveCount,
                        isFastEstimate: !stats.isComplete
                    )
                )

            default:
                throw OpeningBookSessionError.unsupportedExtension(url.pathExtension)
            }
        } catch {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    func moves(for position: ImmutablePosition, ply: Int) throws -> [OpeningBookMove] {
        let bookPly = max(ply, 1)
        let sfen = position.getSFEN(nextPly: bookPly)

        switch storage {
        case let .text(reader):
            let exactMoves = try reader.moves(
                forSFEN: sfen,
                ignoreBookPly: true
            )
            if !exactMoves.isEmpty {
                return exactMoves
            }
            guard let flippedSFEN = OpeningBookParser.flippedSFENKey(
                sfen,
                ignoreBookPly: true
            ) else {
                return []
            }
            return try reader.moves(
                forSFEN: flippedSFEN,
                ignoreBookPly: true
            ).compactMap(OpeningBookParser.flippedOpeningBookMove)

        case let .binary(reader):
            let exactMoves = try reader.moves(
                for: position,
                bookPly: bookPly,
                ignoreBookPly: true
            )
            if !exactMoves.isEmpty {
                return exactMoves
            }
            guard let flippedSFEN = OpeningBookParser.flippedSFENKey(
                sfen,
                ignoreBookPly: true
            ),
            let flippedPosition = Position.fromSFEN(flippedSFEN)
            else {
                return []
            }
            return try reader.moves(
                for: flippedPosition,
                bookPly: bookPly,
                ignoreBookPly: true
            ).compactMap(OpeningBookParser.flippedOpeningBookMove)
        }
    }
}
