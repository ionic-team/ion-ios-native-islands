#if canImport(UIKit)
import Foundation

/// Startup trace, iOS half (task 32/44; Android twin: NIStartupTrace in NISnapshot.kt).
/// Milestones as ms since PROCESS start; read from DevTools via `NativeIslands.startupTrace()`
/// (auto-logged by the web runtime ~2.5s after start).
public enum NIStartupTrace {
    private static let queue = DispatchQueue(label: "ni.startuptrace")
    private static var marks: [(String, Int64)] = []

    /// Process start via kinfo_proc — the same zero the user's launch experience starts from.
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let ok = sysctl(&mib, 4, &info, &size, nil, 0) == 0
        guard ok else { return Date() }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }()

    public static func mark(_ name: String) {
        queue.sync {
            guard !marks.contains(where: { $0.0 == name }) else { return }
            marks.append((name, Int64(Date().timeIntervalSince(processStart) * 1000)))
        }
    }

    public static func snapshot() -> [String: Int64] {
        queue.sync { Dictionary(uniqueKeysWithValues: marks) }
    }
}
#endif
