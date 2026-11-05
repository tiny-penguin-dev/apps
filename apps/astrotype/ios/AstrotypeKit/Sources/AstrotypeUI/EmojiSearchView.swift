#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// A rounded search field on `key`: a magnifier, the text (or a placeholder), a caret
/// while typing goes into it, and × to clear (features/emoji-search). It only shows
/// text: the keyboard's own keys type into it, through the model.
///
///     let field = SearchField(placeholder: "Search emoji")
///     field.text = "pizza"; field.isTyping = true
///     field.onClear = { model.clearSearch() }
final class SearchField: UIControl {
    var text = "" {
        didSet { if text != oldValue { refresh() } }
    }
    /// Whether the keys type into it now: shows the caret and the × (when there is text).
    var isTyping = false {
        didSet { if isTyping != oldValue { refresh() } }
    }
    var onClear: (() -> Void)?

    static let height: CGFloat = 36

    private let placeholder: String
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
    private let label = UILabel()
    private let caret = UIView()
    private let clear = UIButton(type: .system)

    init(placeholder: String) {
        self.placeholder = placeholder
        super.init(frame: .zero)
        backgroundColor = Theme.ui(.key)
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        icon.tintColor = Theme.ui(.muted)
        addSubview(icon)
        label.font = Theme.uiFont(size: 16, weight: .semibold)
        label.lineBreakMode = .byTruncatingHead
        addSubview(label)
        caret.backgroundColor = Theme.ui(.accent)
        caret.layer.cornerRadius = 1
        caret.isUserInteractionEnabled = false
        addSubview(caret)
        clear.setImage(UIImage(systemName: "xmark.circle.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
        clear.tintColor = Theme.ui(.muted)
        clear.accessibilityLabel = "Clear"
        clear.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .touchUpInside)
        addSubview(clear)
        isAccessibilityElement = true
        accessibilityTraits = .searchField
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func refresh() {
        let empty = text.isEmpty
        label.text = empty ? placeholder : text
        label.textColor = Theme.ui(empty ? .muted : .keyInk)
        clear.isHidden = !(isTyping && !empty)
        caret.isHidden = !isTyping
        accessibilityLabel = placeholder
        accessibilityValue = empty ? nil : text
        blink()
        setNeedsLayout()
    }

    /// The caret blinks like a text field's, unless Reduce Motion is on.
    private func blink() {
        caret.layer.removeAllAnimations()
        guard isTyping, !UIAccessibility.isReduceMotionEnabled else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        caret.layer.add(animation, forKey: "blink")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        icon.frame = CGRect(x: 12, y: (h - 18) / 2, width: 18, height: 18)
        icon.contentMode = .center
        let right = clear.isHidden ? bounds.width - 12 : bounds.width - 40
        clear.frame = CGRect(x: bounds.width - 44, y: (h - 44) / 2, width: 44, height: 44)
        let left = icon.frame.maxX + 8
        let room = max(0, right - left - 4)
        let fits = min(room, ceil(label.intrinsicContentSize.width))
        label.frame = CGRect(x: left, y: 0, width: text.isEmpty ? room : fits, height: h)
        caret.frame = CGRect(x: text.isEmpty ? left - 1 : label.frame.maxX + 1, y: (h - 20) / 2, width: 2, height: 20)
    }

    /// The × takes touches past its little circle.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !clear.isHidden, clear.frame.insetBy(dx: -4, dy: 0).contains(point) { return clear }
        return super.hitTest(point, with: event)
    }
}

/// What sits above the keys while emoji search is open: the search field, then one row
/// of results in the guesses bar's place (features/emoji-search). Before anything is
/// typed the row shows Frequently used; with no match it says so.
///
///     let view = EmojiSearchView()
///     view.show(query: "heart", results: [("❤️", "❤️"), ("🩷", "🩷")])
///     view.onEmoji = { form, base in model.typeFromSearch(emoji: form, base: base) }
final class EmojiSearchView: UIView {
    var onEmoji: ((_ form: String, _ base: String) -> Void)?
    var onClear: (() -> Void)?

    /// The field's row and the results' row, one bar high each.
    static let height = KeyboardView.barHeight * 2

    let field = SearchField(placeholder: "Search emoji")
    private let row = FadingRow()
    private let none = UILabel()
    private var buttons: [UIButton] = []
    private var shown: [(form: String, base: String)] = []
    private var shownQuery = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        field.isTyping = true
        field.onClear = { [weak self] in self?.onClear?() }
        addSubview(field)
        row.showsHorizontalScrollIndicator = false
        row.alwaysBounceHorizontal = true
        row.accessibilityLabel = "Results"
        addSubview(row)
        none.font = Theme.uiFont(size: 15, weight: .semibold)
        none.textColor = Theme.ui(.muted)
        none.textAlignment = .center
        addSubview(none)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The search and its results, best first (forms in the picked skin tone, with the
    /// emoji they belong to).
    func show(query: String, results: [(form: String, base: String)]) {
        field.text = query
        let same = results.map(\.form) == shown.map(\.form)
        if !same {
            shown = results
            buttons.forEach { $0.removeFromSuperview() }
            buttons = results.map { item in
                let button = UIButton(type: .custom)
                button.setTitle(item.form, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 29)
                button.layer.cornerRadius = 10
                button.accessibilityLabel = item.form
                button.accessibilityTraits = .keyboardKey
                button.addAction(UIAction { [weak self, weak button] _ in
                    if let button { self?.pop(button) }
                    self?.onEmoji?(item.form, item.base)
                }, for: .touchUpInside)
                row.addSubview(button)
                return button
            }
            row.contentOffset = .zero
            setNeedsLayout()
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        none.text = "No emoji for \u{201C}\(trimmed)\u{201D}"
        none.isHidden = !results.isEmpty || trimmed.isEmpty
        if trimmed != shownQuery {
            shownQuery = trimmed
            // VoiceOver hears how many it found once the typing settles.
            if UIAccessibility.isVoiceOverRunning, !trimmed.isEmpty {
                let count = results.count
                UIAccessibility.post(notification: .announcement,
                                     argument: count == 0 ? "No emoji" : count == 1 ? "1 emoji" : "\(count) emoji")
            }
        }
    }

    private func pop(_ button: UIButton) {
        guard !UIAccessibility.isReduceMotionEnabled, let label = button.titleLabel else { return }
        UIView.animate(withDuration: Theme.Motion.keyHit / 2, animations: {
            label.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }, completion: { _ in
            UIView.animate(withDuration: Theme.Motion.keyHit / 2) { label.transform = .identity }
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bar = KeyboardView.barHeight
        field.frame = CGRect(x: 8, y: (bar - SearchField.height) / 2 + 2, width: bounds.width - 16, height: SearchField.height)
        row.frame = CGRect(x: 0, y: bar, width: bounds.width, height: bar)
        none.frame = row.frame.insetBy(dx: 16, dy: 0)
        let size: CGFloat = 42
        var x: CGFloat = 6
        for button in buttons {
            button.frame = CGRect(x: x, y: (bar - size) / 2, width: size, height: size)
            x += size + 2
        }
        row.contentSize = CGSize(width: x + 4, height: bar)
    }
}

/// The results' row, fading out at the left and right where there are more.
private final class FadingRow: UIScrollView {
    override func layoutSubviews() {
        super.layoutSubviews()
        fadeEdges(.horizontal)
    }
}
#endif
