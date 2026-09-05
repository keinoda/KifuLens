import Foundation

enum RecordSaveError: LocalizedError, Equatable {
    case emptyFileName
    case invalidFileName(String)
    case fileAlreadyExists(String)
    case noChanges(String)

    var errorDescription: String? {
        switch self {
        case .emptyFileName:
            return "ファイル名を入力してください。"
        case let .invalidFileName(fileName):
            return "使用できないファイル名です: \(fileName)"
        case let .fileAlreadyExists(fileName):
            return "同名の棋譜ファイルが既にあります: \(fileName)"
        case let .noChanges(fileName):
            return "\(fileName) には保存する変更がありません。"
        }
    }
}

struct RecordSaveService {
    let directory: URL

    init(
        directory: URL = KifuLensFileDirectories().recordDirectory
    ) {
        self.directory = directory
    }

    static func suggestedFileName(for title: String) -> String {
        var baseName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        baseName = baseName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if baseName.isEmpty || baseName == "新しい盤面" {
            baseName = "棋譜"
        }
        if !baseName.lowercased().hasSuffix(".kif") {
            baseName += ".kif"
        }
        return baseName
    }

    func save(kifText: String, named fileName: String) throws -> URL {
        let url = try destinationURL(named: fileName)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw RecordSaveError.fileAlreadyExists(url.lastPathComponent)
        }

        try write(kifText, to: url)
        return url
    }

    func overwrite(kifText: String, at sourceURL: URL) throws -> URL {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try write(kifText, to: sourceURL)
        return sourceURL
    }

    func destinationURL(named fileName: String) throws -> URL {
        directory.appendingPathComponent(
            try normalizedFileName(fileName),
            isDirectory: false
        )
    }

    private func normalizedFileName(_ fileName: String) throws -> String {
        var normalized = fileName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw RecordSaveError.emptyFileName
        }
        guard normalized.range(
            of: "[/:]",
            options: .regularExpression
        ) == nil else {
            throw RecordSaveError.invalidFileName(normalized)
        }
        let lowercased = normalized.lowercased()
        if !lowercased.hasSuffix(".kif") && !lowercased.hasSuffix(".kifu") {
            normalized += ".kif"
        }
        return normalized
    }

    private func write(_ kifText: String, to url: URL) throws {
        if let data = kifText.data(using: .shiftJIS) {
            try data.write(to: url, options: .atomic)
        } else {
            try kifText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
