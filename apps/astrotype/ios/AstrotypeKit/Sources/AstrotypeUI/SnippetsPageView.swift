#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The snippet page (features/text-replacements): the person's text replacements in a
/// list, each with its shortcut and its phrase, over a strip with `ABC`, the page's
/// title and delete. Tapping one writes its phrase at the cursor. It takes the room of
/// the guesses bar and the keys together, like the emoji page, and is opened from the
/// bar's text button.
///
///     let page = SnippetsPageView(items: model.snippets)
///     page.onPick = { shortcut in model.write(replacement: shortcut) }
///     page.onABC = { hideSnippets() }
final class SnippetsPageView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onPick: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onDelete: (() -> Void)?

    static let stripHeight: CGFloat = 44

    private let items: [TextReplacement]
    private let table = UITableView(frame: .zero, style: .plain)
    private let strip = UIView()
    private let title = UILabel()
    private let empty = UILabel()
    private let abc = EmojiStripKey(title: "ABC")
    private let delete = EmojiStripKey(symbol: "delete.left")

    init(items: [TextReplacement]) {
        self.items = items
        super.init(frame: .zero)
        backgroundColor = .clear

        table.backgroundColor = .clear
        table.separatorColor = Theme.ui(.line)
        table.separatorInset = UIEdgeInsets(top: 0, left: Theme.Space.m, bottom: 0, right: Theme.Space.m)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 52
        table.register(SnippetCell.self, forCellReuseIdentifier: SnippetCell.id)
        table.isHidden = items.isEmpty
        addSubview(table)

        empty.text = "No text replacements yet. Add them in the Astrotype app, under Your words."
        empty.numberOfLines = 0
        empty.textAlignment = .center
        empty.font = Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 18)
        empty.textColor = Theme.ui(.muted)
        empty.isHidden = !items.isEmpty
        addSubview(empty)

        addSubview(strip)
        abc.accessibilityLabel = "Letters"
        abc.addAction(UIAction { [weak self] _ in self?.onABC?() }, for: .touchUpInside)
        strip.addSubview(abc)
        delete.accessibilityLabel = "Delete"
        delete.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        strip.addSubview(delete)
        title.text = "Text replacements"
        title.textAlignment = .center
        title.font = Theme.uiFont(size: 14, weight: .bold, scaledWith: .footnote, upTo: 16)
        title.textColor = Theme.ui(.muted)
        title.accessibilityTraits = .header
        strip.addSubview(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let stripTop = bounds.height - Self.stripHeight
        table.frame = CGRect(x: 0, y: 0, width: bounds.width, height: stripTop)
        empty.frame = CGRect(x: 0, y: 0, width: bounds.width, height: stripTop).insetBy(dx: Theme.Space.xl, dy: Theme.Space.m)
        strip.frame = CGRect(x: 0, y: stripTop, width: bounds.width, height: Self.stripHeight)
        let keyWidth: CGFloat = 52, keyHeight: CGFloat = 36, y = (Self.stripHeight - keyHeight) / 2
        abc.frame = CGRect(x: 4, y: y, width: keyWidth, height: keyHeight)
        delete.frame = CGRect(x: bounds.width - 4 - keyWidth, y: y, width: keyWidth, height: keyHeight)
        title.frame = CGRect(x: abc.frame.maxX + 8, y: 0, width: max(0, delete.frame.minX - abc.frame.maxX - 16),
                             height: Self.stripHeight)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SnippetCell.id, for: indexPath)
        (cell as? SnippetCell)?.show(items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onPick?(items[indexPath.row].shortcut)
    }
}

/// One replacement on the snippet page: the phrase, as written with its variables, on
/// two lines at most, and the shortcut under it.
private final class SnippetCell: UITableViewCell {
    static let id = "snippet"
    private let phrase = UILabel()
    private let shortcut = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let pressed = UIView()
        pressed.backgroundColor = Theme.ui(.keyPressed)
        selectedBackgroundView = pressed
        phrase.numberOfLines = 2
        phrase.font = Theme.uiFont(size: 16, weight: .semibold, scaledWith: .body, upTo: 19)
        phrase.textColor = Theme.ui(.keyInk)
        shortcut.font = Theme.uiFont(size: 13, weight: .bold, scaledWith: .footnote, upTo: 15)
        shortcut.textColor = Theme.ui(.muted)
        let stack = UIStackView(arrangedSubviews: [phrase, shortcut])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Space.m),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Space.m),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Space.s),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.Space.s),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ item: TextReplacement) {
        phrase.text = TextReplacements.oneLine(item.phrase)
        shortcut.text = item.shortcut
        accessibilityLabel = TextReplacements.oneLine(item.phrase)
        accessibilityHint = "Shortcut \(item.shortcut). Writes it."
    }
}
#endif
