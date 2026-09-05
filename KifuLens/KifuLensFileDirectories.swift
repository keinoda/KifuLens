import Foundation

struct KifuLensFileDirectories {
    let documentsDirectory: URL

    init(
        documentsDirectory: URL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    ) {
        self.documentsDirectory = documentsDirectory
    }

    var recordDirectory: URL {
        documentsDirectory.appendingPathComponent("kif", isDirectory: true)
    }

    var bookDirectory: URL {
        documentsDirectory.appendingPathComponent("book", isDirectory: true)
    }

    var referenceDirectory: URL {
        documentsDirectory.appendingPathComponent("reference", isDirectory: true)
    }

    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: recordDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: bookDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: referenceDirectory,
            withIntermediateDirectories: true
        )
    }
}
