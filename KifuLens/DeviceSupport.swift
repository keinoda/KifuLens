import Darwin
import SwiftUI

enum KifuLensDeviceSupport {
    static let minimumChipName = "A13"

    private static let supportedCPUFamilies: Set<UInt32> = [
        UInt32(CPUFAMILY_ARM_LIGHTNING_THUNDER),
        UInt32(CPUFAMILY_ARM_FIRESTORM_ICESTORM),
        UInt32(CPUFAMILY_ARM_BLIZZARD_AVALANCHE),
        UInt32(CPUFAMILY_ARM_EVEREST_SAWTOOTH),
        UInt32(CPUFAMILY_ARM_IBIZA),
        UInt32(CPUFAMILY_ARM_PALMA),
        UInt32(CPUFAMILY_ARM_COLL),
        UInt32(CPUFAMILY_ARM_LOBOS),
        UInt32(CPUFAMILY_ARM_DONAN),
        UInt32(CPUFAMILY_ARM_BRAVA),
        UInt32(CPUFAMILY_ARM_TAHITI),
        UInt32(CPUFAMILY_ARM_TUPAI),
        UInt32(CPUFAMILY_ARM_THERA),
        UInt32(CPUFAMILY_ARM_TILOS),
    ]

    static var isCurrentDeviceSupported: Bool {
#if targetEnvironment(simulator)
        true
#else
        guard let cpuFamily = currentCPUFamily else {
            return false
        }
        return isA13OrNewer(cpuFamily: cpuFamily)
#endif
    }

    static var currentCPUFamily: UInt32? {
        var value: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname(
            "hw.cpufamily",
            &value,
            &size,
            nil,
            0
        ) == 0 else {
            return nil
        }
        return value
    }

    static func isA13OrNewer(cpuFamily: UInt32) -> Bool {
        supportedCPUFamilies.contains(cpuFamily)
    }
}

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 38))
                .foregroundStyle(KifuLensTheme.secondaryText)

            Text("この端末には対応していません")
                .font(.headline)
                .foregroundStyle(KifuLensTheme.primaryText)

            Text("棋譜レンズはA13以降のiPhoneに対応しています。")
                .font(.subheadline)
                .foregroundStyle(KifuLensTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KifuLensTheme.background)
        .accessibilityIdentifier("unsupportedDeviceView")
    }
}
