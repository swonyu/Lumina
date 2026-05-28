import SwiftUI

// Temporary performance helpers for debugging lag (remove in release builds)
#if DEBUG
extension View {
    func debugBodyTime(label: String) -> some View {
        let start = CFAbsoluteTimeGetCurrent()
        return self.onAppear {
            let time = CFAbsoluteTimeGetCurrent() - start
            if time > 0.01 {  // Only log slow ones
                print("⚠️ [Perf] \(label) body took \(String(format: "%.2f", time * 1000))ms")
            }
        }
    }
}
#endif
