import Foundation
import SwiftShogi

enum RecordImportError: LocalizedError {
    case unreadableText
    case emptyText
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "UTF-8またはShift_JISの棋譜として読み取れませんでした。"
        case .emptyText:
            return "棋譜テキストが空です。"
        case let .unsupportedFormat(format):
            return "\(format)形式は棋譜レンズの読み取り対象ではありません。"
        }
    }
}

struct RecordImportPayload {
    let record: SwiftShogi.Record
    let title: String
    let sourceURL: URL?
    let sourceFileName: String?
    let canOverwriteSource: Bool
}

enum RecordImportService {
    static func load(url: URL) throws -> RecordImportPayload {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let text = decode(data) else {
            throw RecordImportError.unreadableText
        }

        return try load(
            text: text,
            fileExtension: url.pathExtension.lowercased(),
            title: url.deletingPathExtension().lastPathComponent,
            sourceURL: url,
            sourceFileName: url.lastPathComponent
        )
    }

    static func load(
        text: String,
        title: String = "棋譜"
    ) throws -> RecordImportPayload {
        try load(
            text: text,
            fileExtension: nil,
            title: title,
            sourceURL: nil,
            sourceFileName: nil
        )
    }

    private static func load(
        text: String,
        fileExtension: String?,
        title: String,
        sourceURL: URL?,
        sourceFileName: String?
    ) throws -> RecordImportPayload {
        let importText = normalizedRecordText(text)
        let normalized = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw RecordImportError.emptyText
        }

        let format: RecordFormatType
        switch fileExtension ?? "" {
        case "kif", "kifu":
            format = .KIF
        case "ki2", "ki2u":
            format = .KI2
        case "csa":
            format = .CSA
        case "sfen":
            format = .SFEN
        case "usi":
            format = .USI
        default:
            format = FormatDetector.detectRecordFormat(normalized)
        }

        let record: SwiftShogi.Record
        switch format {
        case .KIF:
            record = try KakinokiFormatter.importKIF(importText).get()
        case .KI2:
            record = try KakinokiFormatter.importKI2(importText).get()
        case .CSA:
            record = try CSAFormatter.importCSA(importText).get()
        case .SFEN:
            record = try SFENFormatter.importSFEN(normalized).get()
        case .USI:
            record = try SFENFormatter.importUSI(normalized).get()
        case .JKF, .USEN:
            throw RecordImportError.unsupportedFormat(format.rawValue)
        }

        record.goto(0)
        return RecordImportPayload(
            record: record,
            title: title,
            sourceURL: sourceURL,
            sourceFileName: sourceFileName,
            canOverwriteSource: sourceURL != nil && format == .KIF
        )
    }

    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .shiftJIS)
    }

    private static func normalizedRecordText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.first == "\u{feff}" {
            normalized.removeFirst()
        }
        return normalized
    }
}
