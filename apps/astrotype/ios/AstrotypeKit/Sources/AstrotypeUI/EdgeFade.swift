#if canImport(UIKit)
import UIKit

extension UIScrollView {
    /// Fades the content out at the edges along `axis` where more of it is hidden, so it
    /// doesn't stop at a hard line (Gabriel, 5 Nov 2026). An edge with nothing past it
    /// stays sharp, and its fade grows in over the first `length` points of scrolling.
    ///
    /// A gradient mask on the scroll view's own layer: it only clips what the scroll
    /// view already clips, so views it hosts outside itself (the tone picker, the
    /// header's room above the panel) are untouched. Call it from `layoutSubviews`,
    /// which runs on every scroll, since the mask must follow `bounds`.
    ///
    ///     override func layoutSubviews() {
    ///         super.layoutSubviews()
    ///         fadeEdges(.vertical)
    ///     }
    func fadeEdges(_ axis: NSLayoutConstraint.Axis, length: CGFloat = 20) {
        let gradient: CAGradientLayer
        if let existing = layer.mask as? CAGradientLayer {
            gradient = existing
        } else {
            gradient = CAGradientLayer()
            gradient.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
            layer.mask = gradient
        }
        let inset = adjustedContentInset
        let extent: CGFloat, before: CGFloat, after: CGFloat
        if axis == .vertical {
            extent = bounds.height
            before = contentOffset.y + inset.top
            after = contentSize.height + inset.bottom - (contentOffset.y + bounds.height)
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        } else {
            extent = bounds.width
            before = contentOffset.x + inset.left
            after = contentSize.width + inset.right - (contentOffset.x + bounds.width)
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
        }
        guard extent > 0 else { return }
        let start = min(max(0, before), length) / extent
        let end = min(max(0, after), length) / extent
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.locations = [0, start, 1 - end, 1].map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }
}
#endif
