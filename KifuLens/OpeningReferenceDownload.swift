import CryptoKit
import Foundation
import SwiftShogi

struct OpeningReferenceCatalog: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let file: BundledOpeningReferenceFile
        let url: URL
    }

    let formatVersion: Int
    let revision: String
    let displayName: String
    let startDate: String
    let endDate: String
    let minimumRating: Int
    let gameCount: Int
    let files: [Entry]

    func validate() throws {
        guard formatVersion == 1, !revision.isEmpty, !displayName.isEmpty,
              minimumRating == BundledOpeningReference.minimumRating,
              gameCount > 0, !files.isEmpty,
              startDate <= endDate,
              Set(files.map(\.file.extractedFileName)).count == files.count
        else { throw OpeningReferenceDownloadError.invalidCatalog }
        for entry in files {
            let file = entry.file
            let name = file.extractedFileName
            guard entry.url.scheme == "https", entry.url.host != nil,
                  !name.hasPrefix("."), name.hasSuffix(".osref"),
                  !name.contains("/"), !name.contains("\\"),
                  file.compressedByteCount > 0, file.extractedByteCount > 0,
                  [file.compressedSHA256, file.extractedSHA256].allSatisfy({
                      $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) }
                  })
            else { throw OpeningReferenceDownloadError.invalidCatalog }
        }
    }
}

enum OpeningReferenceDownloadError: LocalizedError {
    case invalidCatalog
    case http(Int)
    case notDownloadable
    case checksum(String)
    case incompleteInstallation

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "前例DBの配布情報が不正か、このアプリに対応していません。"
        case let .http(status): return "前例DBの取得先がHTTP \(status)を返しました。時間をおいて再試行してください。"
        case .notDownloadable: return "Google DriveからDBを取得できません。共有設定やダウンロード制限を確認してください。"
        case let .checksum(name): return "前例DB「\(name)」のサイズまたはSHA-256が配布情報と一致しません。現在の前例DBは変更していません。"
        case .incompleteInstallation: return "ダウンロードした前例DBの一部が見つかりません。もう一度取得してください。"
        }
    }
}

struct OpeningReferenceDownloadStore: Sendable {
    let applicationSupportDirectory: URL?

    init(applicationSupportDirectory: URL? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    private var catalogURL: URL {
        get throws {
            try BundledOpeningReferenceInstaller.installationDirectory(
                applicationSupportDirectory: applicationSupportDirectory
            ).appendingPathComponent("downloaded-catalog.json")
        }
    }

    func installedCatalog() throws -> OpeningReferenceCatalog? {
        let url = try catalogURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let catalog = try JSONDecoder().decode(OpeningReferenceCatalog.self, from: Data(contentsOf: url))
        try catalog.validate()
        _ = try installedURLs(for: catalog)
        return catalog
    }

    func installedURLs(for catalog: OpeningReferenceCatalog) throws -> [URL] {
        try catalog.files.map { entry in
            guard let url = try BundledOpeningReferenceInstaller.installedURL(
                for: entry.file, applicationSupportDirectory: applicationSupportDirectory
            ) else { throw OpeningReferenceDownloadError.incompleteInstallation }
            return url
        }
    }

    func save(_ catalog: OpeningReferenceCatalog) throws {
        try catalog.validate()
        _ = try installedURLs(for: catalog)
        // 全ファイルの検証と検索確認が終わるまでは、使用中の版を切り替えない。
        try JSONEncoder().encode(catalog).write(to: catalogURL, options: .atomic)
    }
}

private final class ReferenceTransferProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Int64) -> Void
    init(update: @escaping @Sendable (Int64) -> Void) { self.update = update }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        update(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

struct OpeningReferenceDownloader: Sendable {
    let store: OpeningReferenceDownloadStore
    let session: URLSession

    init(store: OpeningReferenceDownloadStore = .init(), session: URLSession? = nil) {
        self.store = store
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchCatalog(from url: URL) async throws -> OpeningReferenceCatalog {
        guard url.scheme == "https" else { throw OpeningReferenceDownloadError.invalidCatalog }
        let (data, response) = try await session.data(for: URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData
        ))
        try Self.validateResponse(response)
        let catalog: OpeningReferenceCatalog
        do { catalog = try JSONDecoder().decode(OpeningReferenceCatalog.self, from: data) }
        catch { throw OpeningReferenceDownloadError.invalidCatalog }
        try catalog.validate()
        return catalog
    }

    func requiredEntries(for catalog: OpeningReferenceCatalog) throws -> [OpeningReferenceCatalog.Entry] {
        let knownFiles = BundledOpeningReference.files
            + (try store.installedCatalog()?.files.map(\.file) ?? [])
        for entry in catalog.files {
            // 配布ファイル名は版ごとに固定し、使用中のDBを途中で上書きしない。
            if knownFiles.contains(where: {
                $0.extractedFileName == entry.file.extractedFileName
                    && $0.extractedSHA256 != entry.file.extractedSHA256
            }) { throw OpeningReferenceDownloadError.invalidCatalog }
        }
        return try catalog.files.filter {
            try BundledOpeningReferenceInstaller.installedURL(
                for: $0.file, applicationSupportDirectory: store.applicationSupportDirectory
            ) == nil
        }
    }

    func install(
        _ catalog: OpeningReferenceCatalog,
        progress: @escaping @Sendable (Int64, Int64, String) -> Void
    ) async throws -> OpeningReferenceSession {
        try catalog.validate()
        let entries = try requiredEntries(for: catalog)
        let total = entries.reduce(Int64(0)) { $0 + $1.file.compressedByteCount }
        var completed: Int64 = 0
        for entry in entries {
            try Task.checkCancellation()
            let base = completed
            let transfer = ReferenceTransferProgress { received in
                progress(base + min(received, entry.file.compressedByteCount), total, "ダウンロード中")
            }
            let (url, response) = try await session.download(for: URLRequest(url: entry.url), delegate: transfer)
            defer { try? FileManager.default.removeItem(at: url) }
            try Self.validateResponse(response)
            try Self.verifyCompressedFile(at: url, file: entry.file)
            progress(completed, total, "検証・展開中")
            _ = try BundledOpeningReferenceInstaller.install(
                sources: [.init(file: entry.file, compressedURL: url)],
                applicationSupportDirectory: store.applicationSupportDirectory
            )
            completed += entry.file.compressedByteCount
            progress(completed, total, "検証・展開中")
        }
        let urls = try store.installedURLs(for: catalog)
        let reference = try OpeningReferenceSession.open(urls: urls, displayName: catalog.displayName)
        _ = try reference.summary(for: Position())
        try Task.checkCancellation()
        try store.save(catalog)
        return reference
    }

    private static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpeningReferenceDownloadError.notDownloadable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpeningReferenceDownloadError.http(http.statusCode)
        }
        guard response.url?.scheme == "https",
              !(response.mimeType?.contains("html") ?? false)
        else { throw OpeningReferenceDownloadError.notDownloadable }
    }

    static func verifyCompressedFile(at url: URL, file: BundledOpeningReferenceFile) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
            try Task.checkCancellation()
            count += Int64(data.count)
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == file.compressedByteCount, digest == file.compressedSHA256 else {
            throw OpeningReferenceDownloadError.checksum(file.extractedFileName)
        }
    }
}
