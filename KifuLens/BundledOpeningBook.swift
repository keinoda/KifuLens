import Compression
import CryptoKit
import Foundation

enum BundledOpeningBook {
    static let displayName = "ペタショック定跡"
    static let resourceName = "user_book1"
    static let compressedResourceExtension = "ybb.lzfse"
    static let resourceSubdirectory = "OpeningBooks/PetaShock233"
    static let extractedFileName = "user_book1.ybb"
    static let extractedByteCount: Int64 = 195_680_126
    static let extractedSHA256 =
        "915d72caeeffc347ead41c67905f8bdd97218cdec883ee463012105e61af6d08"

    static func compressedURL(
        in bundle: Bundle = .kifuLensApplication
    ) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: compressedResourceExtension,
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(
            forResource: resourceName,
            withExtension: compressedResourceExtension
        )
    }
}

enum BundledOpeningBookInstallationError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case cannotCreateTemporaryFile
    case cannotInitializeDecoder
    case decompressionFailed
    case invalidExtractedFile(byteCount: Int64, sha256: String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "定跡の展開先となるApplication Supportを取得できませんでした。"
        case .cannotCreateTemporaryFile:
            return "定跡を展開する一時ファイルを作成できませんでした。"
        case .cannotInitializeDecoder:
            return "LZFSE定跡の展開処理を開始できませんでした。"
        case .decompressionFailed:
            return "同梱したLZFSE定跡を正しく展開できませんでした。"
        case let .invalidExtractedFile(byteCount, sha256):
            return "展開した定跡の検証に失敗しました（\(byteCount) bytes、SHA-256: \(sha256)）。"
        }
    }
}

struct BundledOpeningBookInstaller {
    private struct DecodedFile {
        let byteCount: Int64
        let sha256: String
    }

    private static let chunkSize = 64 * 1_024
    private static let legacyFileNames = [
        "user_book1.db",
        "user_book1.db.verified",
    ]
    private static let markerContents =
        "\(BundledOpeningBook.extractedByteCount)\n"
            + "\(BundledOpeningBook.extractedSHA256)\n"

    static func install(
        from compressedURL: URL,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let supportDirectory: URL
        if let applicationSupportDirectory {
            supportDirectory = applicationSupportDirectory
        } else {
            guard let defaultDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw BundledOpeningBookInstallationError
                    .applicationSupportDirectoryUnavailable
            }
            supportDirectory = defaultDirectory
        }

        let directory = supportDirectory
            .appendingPathComponent("OpeningBooks", isDirectory: true)
            .appendingPathComponent("PetaShock233", isDirectory: true)
        let destinationURL = directory.appendingPathComponent(
            BundledOpeningBook.extractedFileName
        )
        let markerURL = directory.appendingPathComponent(
            "\(BundledOpeningBook.extractedFileName).verified"
        )

        if try isInstalled(
            at: destinationURL,
            markerURL: markerURL,
            fileManager: fileManager
        ) {
            try excludeFromBackup(directory)
            try removeLegacyFiles(
                from: directory,
                fileManager: fileManager
            )
            return destinationURL
        }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directory)

        let temporaryURL = directory.appendingPathComponent(
            ".\(BundledOpeningBook.extractedFileName).partial"
        )
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        let decoded = try decodeLZFSE(
            from: compressedURL,
            to: temporaryURL,
            fileManager: fileManager
        )
        guard decoded.byteCount == BundledOpeningBook.extractedByteCount,
              decoded.sha256 == BundledOpeningBook.extractedSHA256
        else {
            throw BundledOpeningBookInstallationError.invalidExtractedFile(
                byteCount: decoded.byteCount,
                sha256: decoded.sha256
            )
        }
        try Task.checkCancellation()

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(
                at: temporaryURL,
                to: destinationURL
            )
        }
        try markerContents.write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        try removeLegacyFiles(
            from: directory,
            fileManager: fileManager
        )
        return destinationURL
    }

    private static func removeLegacyFiles(
        from directory: URL,
        fileManager: FileManager
    ) throws {
        for fileName in legacyFileNames {
            let url = directory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func excludeFromBackup(_ directory: URL) throws {
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private static func isInstalled(
        at destinationURL: URL,
        markerURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: destinationURL.path),
              fileManager.fileExists(atPath: markerURL.path)
        else {
            return false
        }

        let attributes = try fileManager.attributesOfItem(
            atPath: destinationURL.path
        )
        guard (attributes[.size] as? NSNumber)?.int64Value
            == BundledOpeningBook.extractedByteCount
        else {
            return false
        }

        return try Data(contentsOf: markerURL)
            == Data(markerContents.utf8)
    }

    private static func decodeLZFSE(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws -> DecodedFile {
        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw BundledOpeningBookInstallationError
                .cannotCreateTemporaryFile
        }

        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: chunkSize
        )
        defer {
            destinationBuffer.deallocate()
        }

        var stream = compression_stream(
            dst_ptr: destinationBuffer,
            dst_size: 0,
            src_ptr: UnsafePointer(destinationBuffer),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(
            &stream,
            COMPRESSION_STREAM_DECODE,
            COMPRESSION_LZFSE
        ) != COMPRESSION_STATUS_ERROR else {
            throw BundledOpeningBookInstallationError
                .cannotInitializeDecoder
        }
        defer {
            compression_stream_destroy(&stream)
        }

        var hash = SHA256()
        var decodedByteCount: Int64 = 0
        var reachedEnd = false

        while !reachedEnd {
            try Task.checkCancellation()
            let sourceData = try input.read(upToCount: chunkSize) ?? Data()
            let isFinal = sourceData.isEmpty

            try sourceData.withUnsafeBytes { sourceBytes in
                stream.src_ptr = sourceBytes
                    .bindMemory(to: UInt8.self)
                    .baseAddress
                    ?? UnsafePointer(destinationBuffer)
                stream.src_size = sourceData.count

                repeat {
                    try Task.checkCancellation()
                    stream.dst_ptr = destinationBuffer
                    stream.dst_size = chunkSize
                    let flags = isFinal
                        ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                        : 0
                    let status = compression_stream_process(
                        &stream,
                        flags
                    )
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw BundledOpeningBookInstallationError
                            .decompressionFailed
                    }

                    let producedByteCount = chunkSize - stream.dst_size
                    if producedByteCount > 0 {
                        let data = Data(
                            bytes: destinationBuffer,
                            count: producedByteCount
                        )
                        try output.write(contentsOf: data)
                        hash.update(data: data)
                        decodedByteCount += Int64(producedByteCount)
                    }

                    if status == COMPRESSION_STATUS_END {
                        reachedEnd = true
                        break
                    }
                    if isFinal,
                       stream.src_size == 0,
                       producedByteCount == 0 {
                        throw BundledOpeningBookInstallationError
                            .decompressionFailed
                    }
                } while stream.src_size > 0
                    || stream.dst_size == 0
                    || isFinal
            }
        }

        let sha256 = hash.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return DecodedFile(
            byteCount: decodedByteCount,
            sha256: sha256
        )
    }
}
