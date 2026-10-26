#if DEBUG
import Darwin
import Foundation
import os
import SwiftUI

/// The launch timeline, measured inside the app from the moment the kernel created the process.
/// The device checklist's D10 reads it instead of timing the launch with XCTest's own clock: over
/// the Wi-Fi tunnel to a phone, XCTest's spawn and polling added about 3 s (±2 s) to every reading
/// (docs/ios/device-checklist-1.4.9.md). Debug builds only: `ios/tools/check_no_test_hooks.sh`
/// proves a release bundle carries none of it.
///
/// Each mark is also a signpost (Points of Interest), so the same timeline shows in Instruments.
enum LaunchClock {
    enum Mark: String, CaseIterable, Sendable {
        case appInit            // SGGSApp.init: the first app code after dyld (and any injected test bootstrap)
        case containerReady     // AppContainer built: corpus opened, bookmarks store opened
        case rootShown          // RootView's first frame (the launch screen hands over here)
        case integrityStart
        case integrityHashed    // the streaming hash, or the cached fingerprint, is settled
        case integrityDone      // the structural checks have run
        case tabsShown          // the TabView mounted
        case nitnemDrawn        // the Nitnem home appeared with its banis loaded (not the skeleton)
    }

    /// Set by D10 only: the Nitnem screen then carries the timeline as an accessibility value.
    static var exposed: Bool { DebugHooks.environment["SGGS_UITEST_LAUNCH_METRICS"] == "1" }

    private static let marks = OSAllocatedUnfairLock<[String: Double]>(initialState: [:])
    private static let signposter = OSSignposter(subsystem: "org.sggs.app", category: .pointsOfInterest)

    /// Record the first occurrence of `mark` (a later one, e.g. a manual re-verify, is ignored).
    static func mark(_ mark: Mark) {
        let now = Date().timeIntervalSince1970
        let first = marks.withLock { m in
            guard m[mark.rawValue] == nil else { return false }
            m[mark.rawValue] = now
            return true
        }
        if first { signposter.emitEvent("launch", "\(mark.rawValue, privacy: .public)") }
    }

    /// When the kernel started this process (Unix time), from its own process record.
    static func processStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
    }

    /// The timeline as JSON: each mark in seconds since the process started.
    static func report(cachedHash: Bool?) -> String {
        let start = processStart()
        let recorded = marks.withLock { $0 }
        var since: [String: Double] = [:]
        for (name, t) in recorded {
            if let start { since[name] = ((t - start) * 1000).rounded() / 1000 }
        }
        var out: [String: Any] = ["since_process_start": since]
        if let cachedHash { out["cached_hash"] = cachedHash }
        let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// An invisible element on the loaded Nitnem home that marks its first appearance and, under D10,
/// carries the launch timeline for the test to read (`launchMetrics`, as its value).
struct LaunchMetricsProbe: View {
    @Environment(AppContainer.self) private var container
    @State private var json = ""

    var body: some View {
        Text(verbatim: " ")
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityIdentifier("launchMetrics")
            .accessibilityValue(json)
            .accessibilityHidden(!LaunchClock.exposed)
            .onAppear {
                LaunchClock.mark(.nitnemDrawn)
                if LaunchClock.exposed { json = LaunchClock.report(cachedHash: container.integrity?.usedCachedHash) }
            }
    }
}
#endif
