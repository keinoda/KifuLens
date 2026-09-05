import Foundation
import SwiftShogi

enum OpeningReferenceError: LocalizedError {
    case noFiles
    case invalidLine
    case invalidUTF8
    case unsupportedExtension(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "前例ファイルが選択されていません。"
        case .invalidLine:
            return "前例ファイルの行形式が不正です。"
        case .invalidUTF8:
            return "前例ファイルをUTF-8として読めません。"
        case let .unsupportedExtension(value):
            return "前例形式「\(value)」には対応していません。.osrefを選んでください。"
        }
    }
}

final class OpeningReferenceSession: @unchecked Sendable {
    let fileName: String
    let fileSize: Int64
    let fileCount: Int
    private let urls: [URL]
    private let scopedURLs: [URL]

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    private init(
        urls: [URL],
        fileName: String,
        scopedURLs: [URL],
        fileManager: FileManager = .default
    ) {
        self.urls = urls
        self.fileName = fileName
        self.scopedURLs = scopedURLs
        fileCount = urls.count
        fileSize = urls.reduce(0) { total, url in
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    deinit {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    static func open(
        url: URL,
        displayName: String? = nil
    ) throws -> OpeningReferenceSession {
        try open(urls: [url], displayName: displayName)
    }

    static func open(
        urls: [URL],
        displayName: String? = nil
    ) throws -> OpeningReferenceSession {
        guard !urls.isEmpty else {
            throw OpeningReferenceError.noFiles
        }
        for url in urls where url.pathExtension.lowercased() != "osref" {
            throw OpeningReferenceError.unsupportedExtension(url.pathExtension)
        }
        let sortedURLs = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                == .orderedAscending
        }
        let scopedURLs = sortedURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        let resolvedName = displayName ?? {
            guard sortedURLs.count > 1 else {
                return sortedURLs[0].lastPathComponent
            }
            return "\(sortedURLs[0].lastPathComponent) ほか\(sortedURLs.count - 1)件"
        }()
        return OpeningReferenceSession(
            urls: sortedURLs,
            fileName: resolvedName,
            scopedURLs: scopedURLs
        )
    }

    func summary(for position: ImmutablePosition) throws -> PrecedentSummary {
        let key = OpeningBookParser.normalizeSFENKey(position.sfen)
        let summaries = try urls.compactMap { url -> PrecedentSummary? in
            try Task.checkCancellation()
            guard let line = try Self.searchLine(url: url, key: key) else {
                return nil
            }
            return try Self.decodeSummary(line)
        }
        return Self.mergeSummaries(summaries)
    }

    private static func mergeSummaries(
        _ summaries: [PrecedentSummary]
    ) -> PrecedentSummary {
        guard !summaries.isEmpty else {
            return .empty
        }
        var movesByUSI: [String: PrecedentMove] = [:]
        for move in summaries.flatMap(\.moves) {
            if let current = movesByUSI[move.usi] {
                movesByUSI[move.usi] = PrecedentMove(
                    usi: current.usi,
                    displayText: current.displayText,
                    count: current.count + move.count,
                    blackWinCount: current.blackWinCount + move.blackWinCount,
                    whiteWinCount: current.whiteWinCount + move.whiteWinCount,
                    drawCount: current.drawCount + move.drawCount
                )
            } else {
                movesByUSI[move.usi] = move
            }
        }
        let moves = movesByUSI.values.sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            return $0.usi < $1.usi
        }
        let examples = summaries.flatMap(\.examples).sorted {
            let lhsDate = dateSortKey($0.dateText)
            let rhsDate = dateSortKey($1.dateText)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if $0.blackName != $1.blackName {
                return $0.blackName < $1.blackName
            }
            if $0.whiteName != $1.whiteName {
                return $0.whiteName < $1.whiteName
            }
            if $0.ply != $1.ply {
                return $0.ply < $1.ply
            }
            return $0.id < $1.id
        }
        return PrecedentSummary(
            occurrenceCount: summaries.reduce(0) {
                $0 + $1.occurrenceCount
            },
            moves: moves,
            examples: Array(examples.prefix(50))
        )
    }

    private static func dateSortKey(_ text: String) -> String {
        var values = text.split { !$0.isNumber }.prefix(6).compactMap { Int($0) }
        guard values.count >= 3, values[0] >= 1900 else {
            return ""
        }
        while values.count < 6 {
            values.append(0)
        }
        return String(
            format: "%04d%02d%02d%02d%02d%02d",
            values[0],
            values[1],
            values[2],
            values[3],
            values[4],
            values[5]
        )
    }

    private static func decodeSummary(_ line: String) throws -> PrecedentSummary {
        guard let tab = line.firstIndex(of: "\t"),
              let data = String(line[line.index(after: tab)...]).data(using: .utf8)
        else {
            throw OpeningReferenceError.invalidLine
        }
        return try JSONDecoder().decode(ReferencePayload.self, from: data).summary
    }

    private struct ReferenceLine {
        let offset: Int64
        let nextOffset: Int64
        let text: String
    }

    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private static func searchLine(url: URL, key: String) throws -> String? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            return nil
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var begin: Int64 = 0
        var end = size
        while begin < end {
            let middle = (begin + end) / 2
            guard let found = try entryLineAtOrAfter(
                handle: handle,
                from: middle,
                fileSize: size
            ) else {
                end = middle
                continue
            }
            let current = keyPrefix(found.text)
            if current == key {
                return found.text
            }
            if key < current {
                end = max(begin, min(found.offset, middle))
            } else {
                begin = max(found.nextOffset, middle + 1)
            }
        }

        var offset = try lineStartAtOrBefore(
            handle: handle,
            offset: begin,
            fileSize: size
        )
        while offset < size,
              let found = try entryLineAtOrAfter(
                  handle: handle,
                  from: offset,
                  fileSize: size
              )
        {
            let current = keyPrefix(found.text)
            if current == key {
                return found.text
            }
            if current > key {
                return nil
            }
            offset = max(found.nextOffset, offset + 1)
        }
        return nil
    }

    private static func keyPrefix(_ line: String) -> String {
        line.firstIndex(of: "\t").map { String(line[..<$0]) } ?? line
    }

    private static func entryLineAtOrAfter(
        handle: FileHandle,
        from offset: Int64,
        fileSize: Int64
    ) throws -> ReferenceLine? {
        var lineOffset = try lineStartAtOrBefore(
            handle: handle,
            offset: offset,
            fileSize: fileSize
        )
        while lineOffset < fileSize {
            guard var line = try readLine(
                handle: handle,
                from: lineOffset,
                fileSize: fileSize
            ) else {
                return nil
            }
            if line.offset == 0 {
                line = ReferenceLine(
                    offset: line.offset,
                    nextOffset: line.nextOffset,
                    text: line.text.replacingOccurrences(
                        of: "\u{FEFF}",
                        with: ""
                    )
                )
            }
            if !line.text.hasPrefix("#"), line.text.contains("\t") {
                return line
            }
            lineOffset = line.nextOffset
        }
        return nil
    }

    private static func lineStartAtOrBefore(
        handle: FileHandle,
        offset requested: Int64,
        fileSize: Int64
    ) throws -> Int64 {
        guard fileSize > 0 else {
            return 0
        }
        var offset = max(0, min(requested, fileSize - 1))
        if offset == 0 || isLineStart(handle: handle, offset: offset) {
            return offset
        }
        while offset > 0 {
            let length = min(4_096, Int(offset))
            let start = offset - Int64(length)
            handle.seek(toFileOffset: UInt64(start))
            let data = handle.readData(ofLength: length)
            if data.isEmpty {
                return 0
            }
            var index = data.count - 1
            while true {
                let byte = data[index]
                if byte == newline || byte == carriageReturn {
                    return start + Int64(index) + 1
                }
                if index == 0 {
                    break
                }
                index -= 1
            }
            offset = start
        }
        return 0
    }

    private static func readLine(
        handle: FileHandle,
        from offset: Int64,
        fileSize: Int64
    ) throws -> ReferenceLine? {
        guard offset < fileSize else {
            return nil
        }
        var data = Data()
        var current = offset
        while current < fileSize {
            let length = min(4_096, Int(fileSize - current))
            handle.seek(toFileOffset: UInt64(current))
            let chunk = handle.readData(ofLength: length)
            if chunk.isEmpty {
                break
            }
            if let newlineIndex = chunk.firstIndex(
                where: { $0 == newline || $0 == carriageReturn }
            ) {
                data.append(chunk[..<newlineIndex])
                var next = current
                    + Int64(newlineIndex - chunk.startIndex + 1)
                if chunk[newlineIndex] == carriageReturn,
                   newlineIndex + 1 < chunk.endIndex,
                   chunk[newlineIndex + 1] == newline
                {
                    next += 1
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    throw OpeningReferenceError.invalidUTF8
                }
                return ReferenceLine(
                    offset: offset,
                    nextOffset: next,
                    text: text
                )
            }
            data.append(chunk)
            current += Int64(chunk.count)
        }
        guard !data.isEmpty else {
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw OpeningReferenceError.invalidUTF8
        }
        return ReferenceLine(
            offset: offset,
            nextOffset: fileSize,
            text: text
        )
    }

    private static func isLineStart(
        handle: FileHandle,
        offset: Int64
    ) -> Bool {
        guard offset > 0 else {
            return true
        }
        handle.seek(toFileOffset: UInt64(offset - 1))
        let byte = handle.readData(ofLength: 1).first
        return byte == newline || byte == carriageReturn
    }
}

private struct ReferencePayload: Decodable {
    let occurrenceCount: Int
    let moves: [ReferenceMovePayload]
    let examples: [ReferenceExamplePayload]

    enum CodingKeys: String, CodingKey {
        case occurrenceCount = "c"
        case moves = "m"
        case examples = "e"
    }

    var summary: PrecedentSummary {
        PrecedentSummary(
            occurrenceCount: occurrenceCount,
            moves: moves.map(\.model),
            examples: examples.map(\.model)
        )
    }
}

private struct ReferenceMovePayload: Decodable {
    let usi: String
    let displayText: String
    let count: Int
    let blackWinCount: Int
    let whiteWinCount: Int
    let drawCount: Int

    enum CodingKeys: String, CodingKey {
        case usi = "u"
        case displayText = "t"
        case count = "c"
        case blackWinCount = "b"
        case whiteWinCount = "w"
        case drawCount = "d"
    }

    var model: PrecedentMove {
        PrecedentMove(
            usi: usi,
            displayText: displayText,
            count: count,
            blackWinCount: blackWinCount,
            whiteWinCount: whiteWinCount,
            drawCount: drawCount
        )
    }
}

private struct ReferenceExamplePayload: Decodable {
    let gameID: UUID
    let fileName: String
    let ply: Int
    let blackName: String
    let whiteName: String
    let dateText: String
    let nextMoveUSI: String
    let nextMoveText: String
    let outcomeCode: String

    enum CodingKeys: String, CodingKey {
        case gameID = "g"
        case fileName = "f"
        case ply = "p"
        case blackName = "b"
        case whiteName = "w"
        case dateText = "d"
        case nextMoveUSI = "u"
        case nextMoveText = "t"
        case outcomeCode = "o"
    }

    var model: PrecedentExample {
        PrecedentExample(
            id: "\(gameID.uuidString)-\(ply)-\(nextMoveUSI)",
            gameID: gameID,
            fileName: fileName,
            ply: ply,
            blackName: blackName,
            whiteName: whiteName,
            dateText: dateText,
            nextMoveUSI: nextMoveUSI,
            nextMoveText: nextMoveText,
            outcome: {
                switch outcomeCode {
                case "b":
                    return .blackWin
                case "w":
                    return .whiteWin
                case "d":
                    return .draw
                default:
                    return .unknown
                }
            }()
        )
    }
}
