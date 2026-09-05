import SwiftUI

@main
struct KifuLensApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            "-show-analysis-settings"
        ) {
            model.detailPanel = .settings
        }
        if ProcessInfo.processInfo.arguments.contains(
            "-show-precedent"
        ) {
            model.detailPanel = .precedent
        }
#endif
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if KifuLensDeviceSupport.isCurrentDeviceSupported {
                    RootView()
                } else {
                    UnsupportedDeviceView()
                }
            }
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        model.pauseAnalysisForBackground()
                    }
                }
        }
    }
}
