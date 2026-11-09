import Foundation
import CoreMotion

final class MotionTracker {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q }()
    private let lock = NSLock()
    private var history: [(Double, Double)] = []
    private var previous: Double?
    private var continuous = 0.0
    private var failure: String?
    var available: Bool { manager.isDeviceMotionAvailable }
    var diagnostic: (ready: Bool, error: String?) {
        lock.lock(); defer { lock.unlock() }
        return (!history.isEmpty, failure)
    }

    func start() {
        guard available, !manager.isDeviceMotionActive else { return }
        lock.lock(); history.removeAll(); previous = nil; continuous = 0; failure = nil; lock.unlock()
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self = self else { return }
            if let error = error { self.lock.lock(); self.failure = error.localizedDescription; self.lock.unlock() }
            guard let motion = motion else { return }
            let g = motion.gravity
            // When facing directly up/down gravity cannot reliably define image roll.
            guard hypot(g.x, g.y) > 0.18 else { return }
            let angle = atan2(g.x, -g.y)
            self.lock.lock()
            if let previous = self.previous {
                let delta = atan2(sin(angle - previous), cos(angle - previous))
                self.continuous += delta
            } else { self.continuous = angle }
            self.previous = angle
            self.failure = nil
            self.history.append((motion.timestamp, self.continuous))
            if self.history.count > 240 { self.history.removeFirst(self.history.count - 240) }
            self.lock.unlock()
        }
    }

    func angle(at time: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let last = history.last else { return 0 }
        // Camera and Core Motion timestamps both use the monotonic host time base.
        for i in history.indices.reversed() where history[i].0 <= time {
            if i + 1 < history.count {
                let a = history[i], b = history[i + 1]
                let t = min(1, max(0, (time - a.0) / max(0.0001, b.0 - a.0)))
                return a.1 + (b.1 - a.1) * t
            }
            return history[i].1
        }
        return abs(last.0 - time) > 2 ? last.1 : (history.first?.1 ?? 0)
    }

    func stop() { manager.stopDeviceMotionUpdates() }
    deinit { stop() }
}
