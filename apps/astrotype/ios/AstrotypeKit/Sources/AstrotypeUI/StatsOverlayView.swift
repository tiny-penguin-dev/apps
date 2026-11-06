#if canImport(UIKit)
import AstrotypeCore
import Synchronization
import UIKit

/// The keyboard's stats overlay (Settings → Debug → "Stats on the keyboard"): three tiny
/// lines in a corner of the keys, "23.4/40 MB · peak 25.1 · 31 left", what it is made
/// of, "heap 12.3 · other 11.1 · 412 layers" (a heap that grows is a leak in our
/// objects; "other" or layers that grow is drawing left behind), and the live counts
/// (`LiveCount`). It shows the keyboard's once-a-second reading (`MemorySample`), the
/// same one the Debug page and the typing log get. It takes no touches, so the keys
/// under it still type. Turns amber past 75% of the 40 MB budget and red past it.
///
///     let stats = StatsOverlayView()
///     stats.isRunning = settings.showsStats
///     stats.show(sample)
public final class StatsOverlayView: UILabel {
    /// The most memory seen since this view was made, in MB.
    public private(set) var peakMB = 0.0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        textColor = Theme.ui(.muted)
        textAlignment = .right
        alpha = 0.85
        numberOfLines = 3
        isHidden = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Whether the overlay shows.
    public var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isHidden = !isRunning
            if isRunning, let sample = MemorySample.now(in: superview) { show(sample) }
        }
    }

    /// Shows a reading, when the overlay is on.
    public func show(_ sample: MemorySample) {
        peakMB = max(peakMB, sample.mb)
        guard isRunning else { return }
        let reading = sample.reading
        text = reading.overlay(peakMB: peakMB) + "\n"
            + MemoryReading.breakdown(footprintMB: sample.mb, heapMB: sample.heap, layers: sample.layers,
                                      views: sample.views, metal: sample.metal)
            + "\n" + sample.counts.line
        textColor = reading.budgetFraction >= 1 ? Theme.ui(.danger)
            : reading.budgetFraction >= 0.75 ? Theme.ui(.sun) : Theme.ui(.muted)
    }
}

public extension MemorySample {
    /// The process's memory now, with the layers and views under `root` (the keyboard).
    @MainActor static func now(in root: UIView?) -> MemorySample? {
        guard let reading = MemoryReading.current() else { return nil }
        return MemorySample(reading: reading, heapMB: MemoryReading.heapMB(), layers: count(root?.layer),
                            views: count(root), metal: MetalKeyboard.loaded)
    }

    /// The views in the tree under `view`, itself included.
    @MainActor private static func count(_ view: UIView?) -> Int {
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
