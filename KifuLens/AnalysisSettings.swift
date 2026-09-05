import Foundation

struct AnalysisEngineIdentifier: RawRepresentable, Hashable, CaseIterable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }

    static let nagisaV3 = Self(rawValue: "nagisa-v3")
    static var allCases: [Self] { AnalysisEngineCatalog.installedEngines.map(\.id) }
}

struct AnalysisEngineDescriptor: Equatable, Identifiable, Sendable {
    let id: AnalysisEngineIdentifier
    let displayName: String
    let version: String
    let commentName: String
}

enum AnalysisTimeLimit: Equatable, Hashable, Sendable {
    case seconds(Int)
    case infinite

    var seconds: Int? {
        guard case let .seconds(value) = self else {
            return nil
        }
        return value
    }

    var goCommand: String {
        switch self {
        case let .seconds(value):
            return "go movetime \(value * 1_000)"
        case .infinite:
            return "go infinite"
        }
    }

    var displayText: String {
        switch self {
        case let .seconds(value):
            return "\(value)秒"
        case .infinite:
            return "無制限"
        }
    }
}

struct EngineUSIOption: Equatable, Sendable {
    let name: String
    let value: String
}

struct BundledEngineConfiguration: Equatable, Sendable {
    let descriptor: AnalysisEngineDescriptor
    let assets: LocalAnalysisAssetSpecification
    let options: [EngineUSIOption]
}

enum AnalysisEngineCatalog {
    static let installedEngines = CompiledEngineConfiguration.engines.map(\.descriptor)
    static let defaultEngine = CompiledEngineConfiguration.defaultEngine.descriptor

    static func configuration(for identifier: AnalysisEngineIdentifier) -> BundledEngineConfiguration? {
        CompiledEngineConfiguration.engines.first { $0.descriptor.id == identifier }
    }

    static func descriptor(for identifier: AnalysisEngineIdentifier) -> AnalysisEngineDescriptor? {
        configuration(for: identifier)?.descriptor
    }

    static func isAvailableForAnalysis(_ identifier: AnalysisEngineIdentifier) -> Bool {
        descriptor(for: identifier) != nil
    }

    @MainActor
    static func makeEngine(for settings: AnalysisSettings) -> LocalAnalysisEngine? {
        guard let entry = configuration(for: settings.engineIdentifier) else { return nil }
        return LocalAnalysisEngine(
            descriptor: entry.descriptor,
            configuration: settings,
            process: EmbeddedUSIProcess.forEngine(settings.engineIdentifier),
            assetSpecification: entry.assets,
            engineOptions: entry.options
        )
    }
}

struct AnalysisSettings: Equatable, Sendable {
    static let `default` = AnalysisSettings(
        engineIdentifier: AnalysisEngineCatalog.defaultEngine.id,
        threadCount: 1,
        hashSizeMB: 256,
        timeLimit: .seconds(10)
    )

    let engineIdentifier: AnalysisEngineIdentifier
    let threadCount: Int
    let hashSizeMB: Int
    let timeLimit: AnalysisTimeLimit
}

enum AnalysisSettingsOptions {
    static let threadCounts = [1, 2, 4]
    static let hashSizesMB = [128, 256, 512, 1_024]
    static let finiteSeconds = 1 ... 60
    static let timeLimits: [AnalysisTimeLimit] = [
        .seconds(1),
        .seconds(3),
        .seconds(5),
        .seconds(10),
        .seconds(30),
        .seconds(60),
        .infinite,
    ]

    static func isValid(_ settings: AnalysisSettings) -> Bool {
        let timeIsValid: Bool
        switch settings.timeLimit {
        case let .seconds(value):
            timeIsValid = finiteSeconds.contains(value)
        case .infinite:
            timeIsValid = true
        }

        return AnalysisEngineCatalog.descriptor(
            for: settings.engineIdentifier
        ) != nil
            && threadCounts.contains(settings.threadCount)
            && hashSizesMB.contains(settings.hashSizeMB)
            && timeIsValid
    }
}

struct AnalysisSettingsStore {
    private enum Key {
        static let engineIdentifier = "analysis.engineIdentifier"
        static let threadCount = "analysis.threadCount"
        static let hashSizeMB = "analysis.hashSizeMB"
        static let moveTimeSeconds = "analysis.moveTimeSeconds"
        static let usesInfiniteTime = "analysis.usesInfiniteTime"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AnalysisSettings {
        let fallback = AnalysisSettings.default
        let engineIdentifier = defaults.string(
            forKey: Key.engineIdentifier
        ).map(AnalysisEngineIdentifier.init(rawValue:))
            .flatMap { AnalysisEngineCatalog.isAvailableForAnalysis($0) ? $0 : nil }
            ?? fallback.engineIdentifier
        let timeLimit: AnalysisTimeLimit
        if defaults.bool(forKey: Key.usesInfiniteTime) {
            timeLimit = .infinite
        } else {
            timeLimit = .seconds(
                integer(
                    forKey: Key.moveTimeSeconds,
                    fallback: fallback.timeLimit.seconds ?? 10
                )
            )
        }
        let candidate = AnalysisSettings(
            engineIdentifier: engineIdentifier,
            threadCount: integer(
                forKey: Key.threadCount,
                fallback: fallback.threadCount
            ),
            hashSizeMB: integer(
                forKey: Key.hashSizeMB,
                fallback: fallback.hashSizeMB
            ),
            timeLimit: timeLimit
        )
        return AnalysisSettingsOptions.isValid(candidate) ? candidate : fallback
    }

    func save(_ settings: AnalysisSettings) {
        defaults.set(
            settings.engineIdentifier.rawValue,
            forKey: Key.engineIdentifier
        )
        defaults.set(settings.threadCount, forKey: Key.threadCount)
        defaults.set(settings.hashSizeMB, forKey: Key.hashSizeMB)
        defaults.set(
            settings.timeLimit == .infinite,
            forKey: Key.usesInfiniteTime
        )
        if let seconds = settings.timeLimit.seconds {
            defaults.set(seconds, forKey: Key.moveTimeSeconds)
        }
    }

    private func integer(forKey key: String, fallback: Int) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }
        return defaults.integer(forKey: key)
    }
}
