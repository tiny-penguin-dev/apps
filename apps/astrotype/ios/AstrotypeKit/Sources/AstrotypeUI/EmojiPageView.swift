#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The emoji page (features/emoji/FEATURE.md): a "Search emoji" field on top
/// (features/emoji-search), then Frequently used and the catalog's categories, four
/// rows high and scrolling sideways, over a strip with `ABC`, one button per category
/// and delete. It takes the room of the guesses bar and the keys
/// together. Holding an emoji that has skin tones opens the `TonePicker`.
///
/// Only the cells on screen are drawn (a collection view), since colour emoji glyphs
/// are the expensive part of this page for the extension's memory.
///
///     let page = EmojiPageView(catalog: catalog)
///     page.frequent = model.emojiHistory.frequent(now: Date())
///     page.tone = { model.emojiHistory.tone(for: $0) }
///     page.onEmoji = { form, base in model.type(emoji: form, base: base) }
///     page.onABC = { hideEmoji() }
final class EmojiPageView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    /// An emoji to type: the form (in its skin tone) and the emoji it belongs to.
    var onEmoji: ((_ form: String, _ base: String) -> Void)?
    /// A skin tone picked on the picker, before `onEmoji` types it.
    var onTone: ((_ form: String, _ base: String) -> Void)?
    var onABC: (() -> Void)?
    var onDelete: (() -> Void)?
    /// The search field was tapped.
    var onSearch: (() -> Void)?
    /// The form to show for an emoji: the tone the person picked, else itself.
    var tone: (String) -> String = { $0 }
    /// Frequently used, as forms. Set when the page opens; it doesn't change while open,
    /// so nothing moves under the thumb.
    var frequent: [String] = [] {
        didSet { if frequent != oldValue { collection.reloadSections(IndexSet(integer: 0)) } }
    }

    static let rows = 4
    /// The search field's row over the grid.
    static let searchRoom = KeyboardView.barHeight
    /// The room the old section titles took, which still sets the emoji size (see
    /// `layoutSubviews`). Sections have no titles (they took a column's width); a gap
    /// and the highlighted category on the strip tell them apart.
    static let topRoom: CGFloat = 20
    /// The gap between sections, on top of each section's 6 pt insets.
    static let sectionGap: CGFloat = 16
    static let stripHeight: CGFloat = 44

    private let catalog: EmojiCatalog
    private let collection: UICollectionView
    private let strip = UIView()
    private let search = SearchField(placeholder: "Search emoji")
    private let abc = EmojiStripKey(title: "ABC")
    private let delete = EmojiStripKey(symbol: "delete.left")
    private var categoryButtons: [UIButton] = []
    private var picker: TonePicker?
    private var cellSize: CGFloat = 37
    private var current = 0
    private var deleteRepeat: Task<Void, Never>?

    init(catalog: EmojiCatalog) {
        self.catalog = catalog
        collection = FadingCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init(frame: .zero)
        backgroundColor = .clear

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        collection.collectionViewLayout = makeLayout()
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        collection.addGestureRecognizer(hold)
        addSubview(collection)
        search.addAction(UIAction { [weak self] _ in self?.closePicker(); self?.onSearch?() }, for: .touchUpInside)
        addSubview(search)

        addSubview(strip)
        abc.accessibilityLabel = "Letters"
        abc.addAction(UIAction { [weak self] _ in self?.closePicker(); self?.onABC?() }, for: .touchUpInside)
        strip.addSubview(abc)
        delete.accessibilityLabel = "Delete"
        delete.addAction(UIAction { [weak self] _ in self?.startDelete() }, for: .touchDown)
        delete.addAction(UIAction { [weak self] _ in self?.stopDelete() },
                         for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        strip.addSubview(delete)
        for section in 0..<numberOfSections(in: collection) {
            let button = UIButton(type: .system)
            let image = UIImage(systemName: Self.symbol(for: category(of: section)),
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            button.setImage(image, for: .normal)
            button.tintColor = Theme.ui(.muted)
            button.layer.cornerRadius = 15
            button.accessibilityLabel = Self.title(for: category(of: section))
            button.addAction(UIAction { [weak self] _ in self?.jump(to: section) }, for: .touchUpInside)
            strip.addSubview(button)
            categoryButtons.append(button)
        }
        markCurrent(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let stripTop = bounds.height - Self.stripHeight
        search.frame = CGRect(x: 8, y: (Self.searchRoom - SearchField.height) / 2 + 2, width: bounds.width - 16,
                              height: SearchField.height)
        let gridHeight = stripTop - Self.searchRoom
        collection.frame = CGRect(x: 0, y: Self.searchRoom, width: bounds.width, height: gridHeight)
        // Four rows fit under the field, but the emoji keep the size five rows had
        // before it (Gabriel likes them a little smaller than Apple's).
        let fiveRows = (stripTop - Self.topRoom - 4) / 5
        let size = max(24, min((gridHeight - 4) / CGFloat(Self.rows), fiveRows).rounded(.down))
        if size != cellSize {
            cellSize = size
            collection.collectionViewLayout.invalidateLayout()
        }
        strip.frame = CGRect(x: 0, y: stripTop, width: bounds.width, height: Self.stripHeight)
        let keyWidth: CGFloat = 52, keyHeight: CGFloat = 36, y = (Self.stripHeight - keyHeight) / 2
        abc.frame = CGRect(x: 4, y: y, width: keyWidth, height: keyHeight)
        delete.frame = CGRect(x: bounds.width - 4 - keyWidth, y: y, width: keyWidth, height: keyHeight)
        let left = abc.frame.maxX + 4, room = delete.frame.minX - 4 - left
        let step = room / CGFloat(max(1, categoryButtons.count))
        for (i, button) in categoryButtons.enumerated() {
            button.frame = CGRect(x: left + step * (CGFloat(i) + 0.5) - 15, y: (Self.stripHeight - 30) / 2, width: 30, height: 30)
        }
    }

    // MARK: Sections

    /// Section 0 is Frequently used; the rest are the catalog's, in order.
    private func category(of section: Int) -> EmojiCategory? {
        section == 0 ? nil : catalog.sections[section - 1].category
    }

    private func form(at indexPath: IndexPath) -> (form: String, base: String, tones: [String]) {
        if indexPath.section == 0 {
            let form = frequent[indexPath.item]
            let emoji = catalog.emoji(for: form)
            return (form, emoji?.text ?? form, emoji?.tones ?? [])
        }
        let emoji = catalog.sections[indexPath.section - 1].emoji[indexPath.item]
        return (emoji.hasTones ? tone(emoji.text) : emoji.text, emoji.text, emoji.tones)
    }

    static func title(for category: EmojiCategory?) -> String {
        category?.title ?? "Frequently Used"
    }

    static func symbol(for category: EmojiCategory?) -> String {
        switch category {
        case nil: "clock"
        case .smileys: "face.smiling"
        case .nature: "leaf"
        case .food: "cup.and.saucer"
        case .activity: "soccerball"
        case .travel: "car"
        case .objects: "lightbulb"
        case .symbols: "heart"
        case .flags: "flag"
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        configuration.interSectionSpacing = Self.sectionGap
        return UICollectionViewCompositionalLayout(sectionProvider: { [weak self] _, environment in
            let size = self?.cellSize ?? 37
            let top = max(0, ((environment.container.contentSize.height - size * CGFloat(Self.rows)) / 2).rounded(.down))
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(size),
                                                                                heightDimension: .absolute(size)))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(size),
                                                   heightDimension: .absolute(size * CGFloat(Self.rows))),
                repeatingSubitem: item, count: Self.rows)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: top, leading: 6, bottom: 0, trailing: 6)
            return section
        }, configuration: configuration)
    }

    // MARK: Data source

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        catalog.sections.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? frequent.count : catalog.sections[section - 1].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: indexPath) as! EmojiCell
        let item = form(at: indexPath)
        cell.show(item.form, size: cellSize, hasTones: !item.tones.isEmpty)
        return cell
    }

    // MARK: Touches

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        closePicker()
        let item = form(at: indexPath)
        (collectionView.cellForItem(at: indexPath) as? EmojiCell)?.pop()
        onEmoji?(item.form, item.base)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        closePicker()
        let point = CGPoint(x: scrollView.contentOffset.x + 24, y: collection.bounds.midY)
        if let path = collection.indexPathForItem(at: point) { markCurrent(path.section) }
    }

    private func jump(to section: Int) {
        closePicker()
        guard collection.numberOfItems(inSection: section) > 0 else { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
        markCurrent(section)
    }

    private func markCurrent(_ section: Int) {
        current = section
        for (i, button) in categoryButtons.enumerated() {
            let on = i == section
            button.tintColor = Theme.ui(on ? .keyInk : .muted)
            button.backgroundColor = on ? Theme.ui(.keyDark) : .clear
            button.accessibilityTraits = on ? [.button, .selected] : .button
        }
    }

    /// Hold an emoji with skin tones: the picker opens over it; slide to a tone and lift,
    /// or lift and tap one.
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let point = gesture.location(in: collection)
            guard let path = collection.indexPathForItem(at: point), let cell = collection.cellForItem(at: path) else { return }
            let item = form(at: path)
            guard !item.tones.isEmpty else { return }
            openPicker(base: item.base, tones: item.tones, current: item.form, over: cell)
        case .changed:
            picker?.highlight(at: gesture.location(in: picker))
        case .ended:
            if let picker, let form = picker.form(at: gesture.location(in: picker)) { pick(form, base: picker.base) }
        default:
            picker?.highlight(at: nil)
        }
    }

    /// The picker for an emoji, above its cell (VoiceOver opens it too, from the cell's
    /// "Skin tones" action).
    fileprivate func openPicker(base: String, tones: [String], current: String, over cell: UIView) {
        closePicker()
        let picker = TonePicker(base: base, forms: [base] + tones, current: current)
        picker.onPick = { [weak self] form in self?.pick(form, base: base) }
        let size = picker.size(cell: cellSize)
        let frame = cell.convert(cell.bounds, to: self)
        let x = min(max(4, frame.midX - size.width / 2), bounds.width - size.width - 4)
        // Above the emoji, or over the top rows when it is near the top (the keyboard
        // can't draw above itself).
        let y = max(0, frame.minY - size.height - 4)
        picker.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        addSubview(picker)
        self.picker = picker
        UIAccessibility.post(notification: .layoutChanged, argument: picker)
    }

    private func pick(_ form: String, base: String) {
        closePicker()
        onTone?(form, base)
        onEmoji?(form, base)
        collection.reloadData()
    }

    func closePicker() {
        picker?.removeFromSuperview()
        picker = nil
    }

    private func startDelete() {
        closePicker()
        onDelete?()
        deleteRepeat?.cancel()
        deleteRepeat = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(KeySurfaceView.holdDelay))
            while !Task.isCancelled {
                self?.onDelete?()
                try? await Task.sleep(for: .seconds(KeySurfaceView.repeatInterval))
            }
        }
    }

    private func stopDelete() {
        deleteRepeat?.cancel()
        deleteRepeat = nil
    }
}

/// One emoji in the grid.
private final class EmojiCell: UICollectionViewCell {
    static let id = "emoji"
    private let label = UILabel()
    private var hasTones = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.baselineAdjustment = .alignCenters
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }

    func show(_ form: String, size: CGFloat, hasTones: Bool) {
        label.text = form
        label.font = .systemFont(ofSize: (size * 0.78).rounded())
        // The emoji itself is the label: VoiceOver speaks its name.
        accessibilityLabel = form
        self.hasTones = hasTones
        accessibilityCustomActions = hasTones
            ? [UIAccessibilityCustomAction(name: "Skin tones") { [weak self] _ in self?.openTones() ?? false }]
            : nil
    }

    private func openTones() -> Bool {
        var view = superview
        while let current = view, !(current is EmojiPageView) { view = current.superview }
        guard let page = view as? EmojiPageView,
              let collection = superview as? UICollectionView,
              let path = collection.indexPath(for: self) else { return false }
        page.openTonesForAccessibility(at: path, cell: self)
        return true
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? Theme.ui(.keyPressed).withAlphaComponent(0.6) : .clear }
    }

    func pop() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        contentView.layer.cornerRadius = 10
        UIView.animate(withDuration: Theme.Motion.keyHit / 2, animations: {
            self.label.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }, completion: { _ in
            UIView.animate(withDuration: Theme.Motion.keyHit / 2) { self.label.transform = .identity }
        })
    }
}

extension EmojiPageView {
    fileprivate func openTonesForAccessibility(at path: IndexPath, cell: UIView) {
        let item = form(at: path)
        guard !item.tones.isEmpty else { return }
        openPicker(base: item.base, tones: item.tones, current: item.form, over: cell)
    }
}

/// `ABC` and delete on the emoji page's strip: function keys, like the keyboard's.
final class EmojiStripKey: UIButton {
    init(title: String? = nil, symbol: String? = nil) {
        super.init(frame: .zero)
        backgroundColor = Theme.ui(.keyDark)
        layer.cornerRadius = Theme.Radius.key
        tintColor = Theme.ui(.keyInk)
        setTitleColor(Theme.ui(.keyInk), for: .normal)
        if let title {
            setTitle(title, for: .normal)
            titleLabel?.font = Theme.uiFont(size: 16, weight: .regular)
        }
        if let symbol {
            setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)),
                     for: .normal)
        }
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = Theme.ui(isHighlighted ? .keyPressed : .keyDark) }
    }
}

/// The skin tones of one emoji: the default form, a thin line, then the five tones,
/// light to dark, with the one in use on `ice`.
final class TonePicker: UIView {
    let base: String
    var onPick: ((String) -> Void)?
    private let forms: [String]
    private var buttons: [UIButton] = []
    private let divider = UIView()

    init(base: String, forms: [String], current: String) {
        self.base = base
        self.forms = forms
        super.init(frame: .zero)
        backgroundColor = Theme.ui(.key)
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 6)
        divider.backgroundColor = Theme.ui(.line)
        addSubview(divider)
        for form in forms {
            let button = UIButton(type: .custom)
            button.setTitle(form, for: .normal)
            button.layer.cornerRadius = 10
            button.backgroundColor = form == current ? Theme.ui(.ice) : .clear
            button.accessibilityLabel = form
            button.addAction(UIAction { [weak self] _ in self?.onPick?(form) }, for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
        accessibilityViewIsModal = true
        if !UIAccessibility.isReduceMotionEnabled {
            transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.9, y: 0.9)
            alpha = 0
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                self.transform = .identity
                self.alpha = 1
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The picker's size for the page's cell size: six buttons a little bigger than a cell.
    func size(cell: CGFloat) -> CGSize {
        let button = max(40, cell + 6)
        return CGSize(width: 12 + CGFloat(forms.count) * button + 9, height: button + 12)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let button = bounds.height - 12
        var x: CGFloat = 6
        for (i, view) in buttons.enumerated() {
            view.frame = CGRect(x: x, y: 6, width: button, height: button)
            view.titleLabel?.font = .systemFont(ofSize: (button * 0.72).rounded())
            x += button
            if i == 0 {
                divider.frame = CGRect(x: x + 4, y: 10, width: 1, height: button - 8)
                x += 9
            }
        }
    }

    /// The form under a point in the picker's coordinates, for a slide and lift.
    func form(at point: CGPoint) -> String? {
        buttons.firstIndex { $0.frame.contains(point) }.map { forms[$0] }
    }

    /// Shows which tone a sliding finger is on.
    func highlight(at point: CGPoint?) {
        for button in buttons {
            button.isHighlighted = point.map { button.frame.contains($0) } ?? false
            button.alpha = button.isHighlighted ? 0.6 : 1
        }
    }
}

/// The emoji grid, fading out at the left and right where there are more emoji.
private final class FadingCollectionView: UICollectionView {
    override func layoutSubviews() {
        super.layoutSubviews()
        fadeEdges(.horizontal)
    }
}
#endif
