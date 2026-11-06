#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The keyboard's stats overlay (Settings → Debug → "Stats on the keyboard"): two tiny
/// lines of memory in a corner of the keys, "23.4/40 MB · peak 25.1 · 31 left" and what
/// it is made of, "heap 12.3 · other 11.1 · 412 layers" (a heap that grows is a leak in
/// our objects; "other" or layers that grow is drawing left behind), read once a second
/// while it shows. It takes no touches, so the keys under it still type.
/// Turns amber past 75% of the 40 MB budget and red past it.
///
///     let stats = StatsOverlayView()
///     stats.isRunning = settings.showsStats
public final class StatsOverlayView: UILabel {
    /// The most memory seen since this view was made, in MB.
    public private(set) var peakMB = 0.0
    private var timer: Timer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        textColor = Theme.ui(.muted)
        textAlignment = .right
        alpha = 0.85
        numberOfLines = 2
        isHidden = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the overlay and reads memory once a second, or hides it and stops.
    public var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isHidden = !isRunning
            if isRunning { start() } else { stop() }
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else if isRunning { start() }
    }

    private func start() {
        guard timer == nil, window != nil else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let reading = MemoryReading.current() else {
            text = "memory unknown"
            return
        }
        peakMB = max(peakMB, reading.footprintMB)
        text = reading.overlay(peakMB: peakMB) + "\n"
            + MemoryReading.breakdown(footprintMB: reading.footprintMB, heapMB: MemoryReading.heapMB(),
                                      layers: Self.count(superview?.layer), views: Self.count(superview),
                                      metal: MetalKeyboard.loaded)
        textColor = reading.budgetFraction >= 1 ? Theme.ui(.danger)
            : reading.budgetFraction >= 0.75 ? Theme.ui(.sun) : Theme.ui(.muted)
    }

    /// The views in the tree under `view`, itself included.
    private static func count(_ view: UIView?) -> Int {
        guard let view else { return 0 }
        return 1 + view.subviews.reduce(0) { $0 + count($1) }
    }

    /// The layers in the tree under `layer`, itself included.
    private static func count(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return 1 + (layer.sublayers ?? []).reduce(0) { $0 + count($1) } + (layer.mask.map { count($0) } ?? 0)
    }
}
#endif
