import Compression
import CryptoKit
import Foundation

struct BundledOpeningReferenceFile: Codable, Equatable, Sendable {
    let resourceName: String
    let compressedByteCount: Int64
    let compressedSHA256: String
    let extractedFileName: String
    let extractedByteCount: Int64
    let extractedSHA256: String
}

struct BundledOpeningReferenceSource: Sendable {
    let file: BundledOpeningReferenceFile
    let compressedURL: URL
}

enum BundledOpeningReference {
    static let displayName = "Floodgate前例 R4000+"
    static let resourceSubdirectory = "FloodgateReference"
    static let compressedResourceExtension = "osref.lzfse"
    static let startDate = "2023-01-01"
    static let endDate = "2026-09-05"
    static let minimumRating = 4_000
    static let gameCount = 57_833

    static let files = [
        BundledOpeningReferenceFile(
            resourceName: "floodgate-4000-since-2023",
            compressedByteCount: 251_937_496,
            compressedSHA256:
                "7cd23355998c109700e587c6d8f420c2b2728748edbceffdd7a0eb8fbd032c86",
            extractedFileName: "floodgate-4000-since-2023.osref",
            extractedByteCount: 2_706_206_825,
            extractedSHA256:
                "65ab0d305572c6c16d20f9295a23f1268ce92a09668e1860d7d35f8741bb39f0"
        ),
        BundledOpeningReferenceFile(
            resourceName:
                "floodgate-4000-since-2023-delta-20260617-20260625",
            compressedByteCount: 2_507_054,
            compressedSHA256:
                "59abbfb88291d12c2dc91109fbc04a59e34d83fc918a753fe22ce998a903eea6",
            extractedFileName:
                "floodgate-4000-since-2023-delta-20260617-20260625.osref",
            extractedByteCount: 32_601_085,
            extractedSHA256:
                "090687bff1cab82171229772f0cbcb890e963da6af2480c304d41a37b58c8909"
        ),
        BundledOpeningReferenceFile(
            resourceName:
                "floodgate-4000-since-2023-delta-20260626-20260813",
            compressedByteCount: 8_045_831,
            compressedSHA256:
                "bcb620158997b160504f63a4c28f60b087e5a7b3ae98939a058163cfd765c52e",
            extractedFileName:
                "floodgate-4000-since-2023-delta-20260626-20260813.osref",
            extractedByteCount: 98_152_935,
            extractedSHA256:
                "5af4a793323daa6ba5366afa06d9956c17ae784e41c5f928758a99fa358cab1c"
        ),
        BundledOpeningReferenceFile(
            resourceName:
                "floodgate-4000-since-2023-delta-20260814-20260905",
            compressedByteCount: 5_801_921,
            compressedSHA256:
                "e45b60192472e974c305a6f983f7a4439777d2810d76be3d195e76790caf2113",
            extractedFileName:
                "floodgate-4000-since-2023-delta-20260814-20260905.osref",
            extractedByteCount: 73_383_976,
            extractedSHA256:
                "e201db79c73be31ac33c77f16a53cce5230999973780ae4c356ef4ac6ce4665c"
        ),
    ]

    static func sources(
        in bundle: Bundle = .kifuLensApplication
    ) throws -> [BundledOpeningReferenceSource] {
        try files.map { file in
            guard let url = bundle.url(
                forResource: file.resourceName,
                withExtension: compressedResourceExtension,
                subdirectory: resourceSubdirectory
            ) ?? bundle.url(
                forResource: file.resourceName,
                withExtension: compressedResourceExtension
            ) else {
                throw BundledOpeningReferenceInstallationError
                    .resourceNotFound(file.resourceName)
            }
            return BundledOpeningReferenceSource(
                file: file,
                compressedURL: url
            )
        }
    }
}

enum BundledOpeningReferenceInstallationError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case cannotCreateTemporaryFile(String)
    case cannotInitializeDecoder
    case decompressionFailed(String)
    case invalidExtractedFile(
        fileName: String,
        byteCount: Int64,
        sha256: String
    )
    case noFiles
    case resourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "前例集の展開先となるApplication Supportを取得できませんでした。"
        case let .cannotCreateTemporaryFile(fileName):
            return "前例集「\(fileName)」の一時ファイルを作成できませんでした。"
        case .cannotInitializeDecoder:
            return "LZFSE前例集の展開処理を開始できませんでした。"
        case let .decompressionFailed(fileName):
            return "同梱した前例集「\(fileName)」を正しく展開できませんでした。"
        case let .invalidExtractedFile(fileName, byteCount, sha256):
            return "展開した前例集「\(fileName)」の検証に失敗しました（\(byteCount) bytes、SHA-256: \(sha256)）。"
        case .noFiles:
            return "同梱前例集のファイル情報がありません。"
        case let .resourceNotFound(resourceName):
            return "同梱した前例集「\(resourceName).osref.lzfse」が見つかりません。"
        }
    }
}

struct BundledOpeningReferenceInstaller {
    private struct DecodedFile {
        let byteCount: Int64
        let sha256: String
    }

    private static let chunkSize = 64 * 1_024

    static func installationDirectory(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let support = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw BundledOpeningReferenceInstallationError.applicationSupportDirectoryUnavailable
        }
        return support.appendingPathComponent("FloodgateReference", isDirectory: true)
            .appendingPathComponent("R4000Since2023", isDirectory: true)
    }

    static func installedURL(
        for file: BundledOpeningReferenceFile,
        applicationSupportDirectory: URL? = nil
    ) throws -> URL? {
        let directory = try installationDirectory(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let url = directory.appendingPathComponent(file.extractedFileName)
        return try isInstalled(
            file: file, at: url,
            markerURL: directory.appendingPathComponent("\(file.extractedFileName).verified"),
            fileManager: .default
        ) ? url : nil
    }

    static func install(
        sources: [BundledOpeningReferenceSource],
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard !sources.isEmpty else {
            throw BundledOpeningReferenceInstallationError.noFiles
        }

        let supportDirectory: URL
        if let applicationSupportDirectory {
            supportDirectory = applicationSupportDirectory
        } else {
            guard let defaultDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw BundledOpeningReferenceInstallationError
                    .applicationSupportDirectoryUnavailable
            }
            supportDirectory = defaultDirectory
        }

        let directory = supportDirectory
            .appendingPathComponent("FloodgateReference", isDirectory: true)
            .appendingPathComponent("R4000Since2023", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directory)

        return try sources.map { source in
            try install(
                source: source,
                into: directory,
                fileManager: fileManager
            )
        }
    }

    private static func install(
        source: BundledOpeningReferenceSource,
        into directory: URL,
        fileManager: FileManager
    ) throws -> URL {
        let file = source.file
        let destinationURL = directory.appendingPathComponent(
            file.extractedFileName
        )
        let markerURL = directory.appendingPathComponent(
            "\(file.extractedFileName).verified"
        )
        if try isInstalled(
            file: file,
            at: destinationURL,
            markerURL: markerURL,
            fileManager: fileManager
        ) {
            return destinationURL
        }

        let temporaryURL = directory.appendingPathComponent(
            ".\(file.extractedFileName).partial"
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
            from: source.compressedURL,
            to: temporaryURL,
            fileName: file.extractedFileName,
            fileManager: fileManager
        )
        guard decoded.byteCount == file.extractedByteCount,
              decoded.sha256 == file.extractedSHA256
        else {
            throw BundledOpeningReferenceInstallationError
                .invalidExtractedFile(
                    fileName: file.extractedFileName,
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
        try markerContents(for: file).write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        return destinationURL
    }

    private static func isInstalled(
        file: BundledOpeningReferenceFile,
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
            == file.extractedByteCount
        else {
            return false
        }
        return try Data(contentsOf: markerURL)
            == Data(markerContents(for: file).utf8)
    }

    private static func markerContents(
        for file: BundledOpeningReferenceFile
    ) -> String {
        "\(file.extractedByteCount)\n\(file.extractedSHA256)\n"
    }

    private static func excludeFromBackup(_ directory: URL) throws {
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private static func decodeLZFSE(
        from sourceURL: URL,
        to destinationURL: URL,
        fileName: String,
        fileManager: FileManager
    ) throws -> DecodedFile {
        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw BundledOpeningReferenceInstallationError
                .cannotCreateTemporaryFile(fileName)
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
            throw BundledOpeningReferenceInstallationError
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
                        throw BundledOpeningReferenceInstallationError
                            .decompressionFailed(fileName)
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
                        throw BundledOpeningReferenceInstallationError
                            .decompressionFailed(fileName)
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
