import AstrotypeCore
import AstrotypeUI
import UIKit

/// Reads the keyboard's memory once a second while it shows (`MemorySample`) and hands
/// the one reading to everything that wants it: the stats overlay, the Debug page's
/// file, the health numbers and the typing log. A reading takes well under a
/// millisecond, layers and views included.
@MainActor
final class MemorySampler {
    /// The keyboard view, whose layers and views are counted.
    var root: () -> UIView? = { nil }
    var onSample: ((MemorySample) -> Void)?
    private var timer: Timer?

    /// A reading now.
    func take() -> MemorySample? {
        MemorySample.now(in: root())
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let sample = take() { onSample?(sample) }
    }
}
