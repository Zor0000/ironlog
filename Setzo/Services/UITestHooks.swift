import Foundation

/// Launch-argument switches consumed by UI tests and evidence capture. All of
/// them are no-ops in Release builds.
enum UITestHooks {
    /// `UITest_Seed <n>`: features that use randomness should swap in a seeded
    /// generator so UI tests and `scripts/capture_evidence.sh` are reproducible.
    static var seed: UInt64? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "UITest_Seed"),
              arguments.indices.contains(index + 1) else { return nil }
        return UInt64(arguments[index + 1])
        #else
        return nil
        #endif
    }
}
