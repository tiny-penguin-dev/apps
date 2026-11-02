#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The in-keyboard settings (DESIGN.md: under the "123" hold), for when Full Access is
/// off and the app's Settings cannot reach the keyboard: autospace, its delay, how
/// strictly it keeps to real words, trails, the guesses bar, the split, and learning
/// from the person (with a forget that asks twice).
///
/// Shown over the keys. The title and Done stay at the top; the rows sit below in
/// three rounded groups (typing, look, learning) that scroll when the keys' space is
/// shorter than the list, so every row can be reached on every phone and text size.
public final class SettingsPanelView: UIView {
    public var settings: KeyboardSettings {
        didSet { render() }
    }
    public var onChange: ((KeyboardSettings) -> Void)?
    public var onDone: (() -> Void)?
    /// Whether the split layout may be turned on (Pro). Off, the row says so and the
    /// switch stays put; the app's Pro screen is where to go.
    public var allowsSplit = true {
        didSet { render() }
    }

    /// A row's least height, the tap target size.
    private static let rowHeight: CGFloat = 44
    private static let headerHeight: CGFloat = 52

    private let title = UILabel()
    private let done = UIButton(configuration: .filled())
    private let scroll = PanelScrollView()
    private let groups = UIStackView()

    private let autospaceLabel = UILabel()
    private let autospaceSwitch = UISwitch()
    private let delayLabel = UILabel()
    private let delayValue = UILabel()
    private let delaySlider = UISlider()
    private var delayRow = UIView()
    private let strictLabel = UILabel()
    private let strictValue = UILabel()
    private let strictSlider = UISlider()
    private let trailsLabel = UILabel()
    private let trailsSwitch = UISwitch()
    private let barLabel = UILabel()
    private let barSwitch = UISwitch()
    private let splitLabel = UILabel()
    private let splitSwitch = UISwitch()
    private let learnLabel = UILabel()
    private let learnSwitch = UISwitch()
    private let forget = UIButton(configuration: .plain())
    /// The first tap on Forget arms it; the second forgets.
    private var forgetArmed = false
    private var flashedIndicators = false

    public init(settings: KeyboardSettings) {
        self.settings = settings
        super.init(frame: .zero)
        backgroundColor = Theme.ui(.kb)

        title.text = "Keyboard settings"
        title.font = Theme.uiFont(size: 17, weight: .heavy)
        title.textColor = Theme.ui(.ink)
        title.accessibilityTraits = .header
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        addSubview(title)

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = Theme.ui(.accent)
        config.baseForegroundColor = Theme.ui(.accentInk)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.l, bottom: 6, trailing: Theme.Space.l)
        config.attributedTitle = AttributedString("Done", attributes: AttributeContainer([.font: Theme.uiFont(size: 15, weight: .bold)]))
        done.configuration = config
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        addSubview(done)

        for (label, text) in [(autospaceLabel, "Autospace"), (delayLabel, "Delay"), (strictLabel, "Real words"), (trailsLabel, "Trails"), (barLabel, "Guesses bar"), (splitLabel, "Split on wide screens"), (learnLabel, "Learn from my typing")] {
            label.text = text
            label.font = Self.rowFont
            label.textColor = Theme.ui(.ink)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }
        for value in [delayValue, strictValue] {
            value.font = Self.rowFont
            value.textColor = Theme.ui(.muted)
            value.textAlignment = .right
            value.adjustsFontForContentSizeCategory = true
        }
        autospaceLabel.accessibilityHint = "Write a swiped word after a short pause"
        barLabel.accessibilityHint = "Show the guesses above the keys on a phone"
        learnLabel.accessibilityHint = "Your words, word pairs and where your thumbs land, kept on this phone"

        for (control, label) in [(autospaceSwitch, autospaceLabel), (trailsSwitch, trailsLabel), (barSwitch, barLabel), (splitSwitch, splitLabel), (learnSwitch, learnLabel)] {
            control.onTintColor = Theme.ui(.accent)
            control.accessibilityLabel = label.text
            control.accessibilityHint = label.accessibilityHint
        }

        delaySlider.minimumValue = Float(KeyboardSettings.delayRange.lowerBound)
        delaySlider.maximumValue = Float(KeyboardSettings.delayRange.upperBound)
        delaySlider.accessibilityLabel = "Autospace delay"
        strictSlider.minimumValue = 0
        strictSlider.maximumValue = 1
        strictSlider.accessibilityLabel = "Real words"
        strictSlider.accessibilityHint = "How sure the keyboard must be of a real word before it puts one in for letters you tapped"
        for slider in [delaySlider, strictSlider] {
            slider.minimumTrackTintColor = Theme.ui(.accent)
        }

        autospaceSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.autospace = self.autospaceSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        delaySlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.autospaceDelay = (Double(self.delaySlider.value) * 10).rounded() / 10
            self.onChange?(self.settings)
        }, for: .valueChanged)
        strictSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.wordStrictness = (Double(self.strictSlider.value) * 100).rounded() / 100
            self.onChange?(self.settings)
        }, for: .valueChanged)
        trailsSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.trails = self.trailsSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        barSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.showsBar = self.barSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        splitSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.splitOnWide = self.splitSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        learnSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.learnsFromYou = self.learnSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)

        var forgetConfig = UIButton.Configuration.plain()
        forgetConfig.contentInsets = .zero
        forgetConfig.baseForegroundColor = Theme.ui(.right)
        forget.configuration = forgetConfig
        forget.contentHorizontalAlignment = .leading
        forget.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.forgetArmed {
                self.forgetArmed = false
                self.settings.forgetPersonalAt = Date()
                self.onChange?(self.settings)
                self.forget.configuration?.attributedTitle = Self.rowTitle("Forgotten")
                self.forget.configuration?.baseForegroundColor = Theme.ui(.muted)
                self.forget.isEnabled = false
            } else {
                self.forgetArmed = true
                self.render()
            }
        }, for: .touchUpInside)

        buildGroups()
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static var rowFont: UIFont {
        Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 22)
    }

    private static func rowTitle(_ text: String) -> AttributedString {
        AttributedString(text, attributes: AttributeContainer([.font: rowFont]))
    }

    // MARK: Building

    private func buildGroups() {
        delayRow = sliderRow(delayLabel, delaySlider, delayValue)
        let strictRow = sliderRow(strictLabel, strictSlider, strictValue)
        // The two sliders start at the same place.
        delayLabel.widthAnchor.constraint(equalTo: strictLabel.widthAnchor).isActive = true

        groups.axis = .vertical
        groups.spacing = Theme.Space.m
        groups.translatesAutoresizingMaskIntoConstraints = false
        groups.addArrangedSubview(group([switchRow(autospaceLabel, autospaceSwitch), delayRow, strictRow]))
        groups.addArrangedSubview(group([switchRow(trailsLabel, trailsSwitch), switchRow(barLabel, barSwitch), switchRow(splitLabel, splitSwitch)]))
        groups.addArrangedSubview(group([switchRow(learnLabel, learnSwitch), row([forget])]))

        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.delaysContentTouches = false
        scroll.backgroundColor = .clear
        scroll.addSubview(groups)
        addSubview(scroll)

        let content = scroll.contentLayoutGuide
        let frame = scroll.frameLayoutGuide
        NSLayoutConstraint.activate([
            groups.topAnchor.constraint(equalTo: content.topAnchor),
            groups.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Theme.Space.m),
            groups.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: Theme.Space.m),
            groups.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -Theme.Space.m),
        ])
    }

    /// A rounded card holding rows, with a hairline between them.
    private func group(_ rows: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.ui(.key)
        card.layer.cornerRadius = Theme.Radius.sm
        card.layer.cornerCurve = .continuous
        let column = UIStackView()
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = UIView()
                line.backgroundColor = Theme.ui(.kb)
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                column.addArrangedSubview(line)
            }
            column.addArrangedSubview(row)
        }
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: card.topAnchor),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Space.m),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Space.m),
        ])
        return card
    }

    private func row(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Theme.Space.m
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.xs, trailing: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.rowHeight).isActive = true
        return row
    }

    /// A name on the left and a switch on the right.
    private func switchRow(_ label: UILabel, _ control: UISwitch) -> UIStackView {
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row([label, control])
    }

    /// A name, a slider, and its value at the end.
    private func sliderRow(_ label: UILabel, _ slider: UISlider, _ value: UILabel) -> UIStackView {
        label.numberOfLines = 1
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return row([label, slider, value])
    }

    // MARK: State

    private func render() {
        autospaceSwitch.isOn = settings.autospace
        trailsSwitch.isOn = settings.trails
        barSwitch.isOn = settings.showsBar
        splitSwitch.isOn = settings.splitOnWide && allowsSplit
        splitSwitch.isEnabled = allowsSplit
        splitLabel.text = allowsSplit ? "Split on wide screens" : "Split on wide screens · PRO"
        splitLabel.alpha = allowsSplit ? 1 : 0.5
        delaySlider.value = Float(settings.autospaceDelay)
        delaySlider.isEnabled = settings.autospace
        delayValue.text = "\(String(format: "%.1f", settings.autospaceDelay)) s"
        delayRow.alpha = settings.autospace ? 1 : 0.45
        learnSwitch.isOn = settings.learnsFromYou
        strictSlider.value = Float(settings.wordStrictness)
        strictValue.text = "\(Int((settings.wordStrictness * 100).rounded()))%"
        if forget.isEnabled {
            forget.configuration?.attributedTitle = Self.rowTitle(forgetArmed ? "Tap again to forget" : "Forget what it learned")
        }
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let side = Theme.Space.m
        let header = Self.headerHeight
        done.sizeToFit()
        let doneSize = CGSize(width: max(80, done.bounds.width), height: 34)
        done.frame = CGRect(x: bounds.maxX - side - doneSize.width, y: (header - doneSize.height) / 2,
                            width: doneSize.width, height: doneSize.height)
        title.frame = CGRect(x: side + Theme.Space.xs, y: 0,
                             width: max(0, done.frame.minX - side - Theme.Space.s), height: header)
        scroll.frame = CGRect(x: 0, y: header, width: bounds.width, height: max(0, bounds.height - header))
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !flashedIndicators else { return }
        flashedIndicators = true
        // Shows there is more below when the list does not fit.
        Task { @MainActor [weak self] in self?.scroll.flashScrollIndicators() }
    }
}

/// Lets a drag that starts on a switch or button scroll the list, while a drag on a
/// slider still moves the slider.
private final class PanelScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        !(view is UISlider)
    }
}
#endif
