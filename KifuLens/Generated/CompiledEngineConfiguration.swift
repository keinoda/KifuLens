// engines.jsonから生成。変更は設定ファイルで行ってください。
enum CompiledEngineConfiguration {
    static let engines: [BundledEngineConfiguration] = [
        BundledEngineConfiguration(
            descriptor: AnalysisEngineDescriptor(
                id: AnalysisEngineIdentifier(rawValue: "nagisa-v3"),
                displayName: "NAGISA v3", version: "v3.1",
                commentName: "NAGISA"
            ),
            assets: LocalAnalysisAssetSpecification(
                directoryName: "nagisa-v3",
                nnueSize: 78442142, progressSize: 1003104,
                bucketMode: "progress8kpabs"
            ),
            options: [EngineUSIOption(name: "FV_SCALE", value: "28"),
                    EngineUSIOption(name: "LS_PROGRESS_COEFF", value: "@progress"),
                    EngineUSIOption(name: "LS_BUCKET_MODE", value: "progress8kpabs")]
        )
    ]
    static let defaultEngine = engines[0]
    static let policyEngine = AnalysisEngineIdentifier(rawValue: "nagisa-v3")
}
