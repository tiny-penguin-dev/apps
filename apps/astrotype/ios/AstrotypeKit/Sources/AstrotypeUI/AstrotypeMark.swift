#if canImport(UIKit)
import UIKit

/// The app icon's mark (an "A" key with two orbits, each a trail fading back round to
/// its dot) as one-colour art for the keyboard's menu button in the guesses bar. A
/// template image from the package's `Media.xcassets`, so it takes the tint it is shown
/// in: the bar's grey, like the pencil (Gabriel, 8 Nov 2026: "just in monochrome gray").
/// It is 30 pt wide, tighter than the icon so it is less wide, with gaps cut round the
/// front of each orbit and where one passes over the other (Gabriel, 9 Nov 2026).
///
/// Drawn in `design/icon/render.html`, with the app icon, and saved by
/// `design/icon/render.cjs`; change it there, not here.
///
///     button.configuration?.image = AstrotypeMark.image
public enum AstrotypeMark {
    /// The mark, 30 × 20 pt, as a template image; an "A" key symbol if the package's
    /// resource bundle is missing.
    @MainActor public static let image: UIImage = {
        let mark = bundles.lazy.compactMap { UIImage(named: "AstrotypeMark", in: $0, compatibleWith: nil) }.first
            ?? UIImage(systemName: "a.square.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
            ?? UIImage()
        return mark.withRenderingMode(.alwaysTemplate)
    }()

    /// This target's resource bundle in the app's or the extension's resources, looked
    /// up by hand like `MetalKeyboard`'s: `Bundle.module` stops the process when it is
    /// missing.
    private static var bundles: [Bundle] {
        [Bundle.main, Bundle(for: Marker.self)].compactMap(\.resourceURL)
            .map { $0.appendingPathComponent("AstrotypeKit_AstrotypeUI.bundle", isDirectory: true) }
            .compactMap { Bundle(url: $0) }
    }

    private final class Marker {}
}
#endif
