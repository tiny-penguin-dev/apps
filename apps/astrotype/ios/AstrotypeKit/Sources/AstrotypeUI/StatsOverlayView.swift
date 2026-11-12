#if canImport(UIKit)
import AstrotypeCore
import Synchronization
import UIKit

/// The keyboard's stats overlay (Settings → Debug → "Stats on the keyboard"): one tiny
/// line centred in the strip below the keys, "23.4 MB · peak 48.1", with more only when
/// something is out of range (`MemorySample.brief`). The full reading goes to the typing
/// log. It shows the keyboard's once-a-second reading (`MemorySample`), the same one the
/// Debug page and the typing log get. It takes no touches. Turns amber from 75% of
/// iOS's limit and red from 90% (`MemoryReading.level`).
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
        font = .monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        textColor = Theme.ui(.muted)
        textAlignment = .center
        alpha = 0.85
        numberOfLines = 1
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
        let line = sample.brief(peakMB: peakMB)
        if line != text {
            text = line
            // The keyboard sizes the overlay to its text.
            superview?.setNeedsLayout()
        }
        switch reading.level(of: reading.footprintMB) {
        case .near: textColor = Theme.ui(.danger)
        case .high: textColor = Theme.ui(.sun)
        case .fine: textColor = Theme.ui(.muted)
        }
    }
}

public extension MemorySample {
    /// The process's memory now, with the layers and views under `root` (the keyboard).
    @MainActor static func now(in root: UIView?) -> MemorySample? {
        guard let reading = MemoryReading.current() else { return nil }
        return MemorySample(reading: reading, heapMB: MemoryReading.heapMB(), layers: count(root?.layer),
                            views: count(root), metal: MetalKeyboard.loaded, split: MemoryReading.split())
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
