#if canImport(UIKit)
import StackWriteCore
import UIKit

/// The in-keyboard settings (DESIGN.md: under the "123" hold), for when Full Access is
/// off and the app's Settings cannot reach the keyboard: autospace, its delay, trails.
/// Shown over the keys; Done puts the keys back.
public final class SettingsPanelView: UIView {
    public var settings: KeyboardSettings {
        didSet { render() }
    }
    public var onChange: ((KeyboardSettings) -> Void)?
    public var onDone: (() -> Void)?

    private let title = UILabel()
    private let autospaceLabel = UILabel()
    private let autospaceSwitch = UISwitch()
    private let delayLabel = UILabel()
    private let delaySlider = UISlider()
    private let trailsLabel = UILabel()
    private let trailsSwitch = UISwitch()
    private let splitLabel = UILabel()
    private let splitSwitch = UISwitch()
    private let done = UIButton(configuration: .filled())

    public init(settings: KeyboardSettings) {
        self.settings = settings
        super.init(frame: .zero)
        backgroundColor = Theme.ui(.kb)

        title.text = "Keyboard settings"
        title.font = Theme.uiFont(size: 15, weight: .heavy)
        title.textColor = Theme.ui(.ink)
        addSubview(title)

        for (label, text) in [(autospaceLabel, "Autospace"), (delayLabel, "Delay"), (trailsLabel, "Trails"), (splitLabel, "Split on wide screens")] {
            label.text = text
            label.font = Theme.uiFont(size: 15, weight: .semibold)
            label.textColor = Theme.ui(.ink)
            addSubview(label)
        }
        autospaceLabel.accessibilityHint = "Write a swiped word after a short pause"
        addSubview(autospaceSwitch)
        addSubview(trailsSwitch)
        addSubview(splitSwitch)

        delaySlider.minimumValue = Float(KeyboardSettings.delayRange.lowerBound)
        delaySlider.maximumValue = Float(KeyboardSettings.delayRange.upperBound)
        delaySlider.minimumTrackTintColor = Theme.ui(.accent)
        delaySlider.accessibilityLabel = "Autospace delay"
        addSubview(delaySlider)

        for control in [autospaceSwitch, trailsSwitch, splitSwitch] {
            control.onTintColor = Theme.ui(.accent)
        }

        autospaceSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.autospace = self.autospaceSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        trailsSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.trails = self.trailsSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        splitSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.splitOnWide = self.splitSwitch.isOn
            self.onChange?(self.settings)
        }, for: .valueChanged)
        delaySlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.settings.autospaceDelay = (Double(self.delaySlider.value) * 10).rounded() / 10
            self.onChange?(self.settings)
        }, for: .valueChanged)

        var config = UIButton.Configuration.filled()
        config.title = "Done"
        config.baseBackgroundColor = Theme.ui(.accent)
        config.baseForegroundColor = Theme.ui(.accentInk)
        config.cornerStyle = .capsule
        done.configuration = config
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        addSubview(done)
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func render() {
        autospaceSwitch.isOn = settings.autospace
        trailsSwitch.isOn = settings.trails
        splitSwitch.isOn = settings.splitOnWide
        delaySlider.value = Float(settings.autospaceDelay)
        delaySlider.isEnabled = settings.autospace
        delayLabel.text = "Delay \(String(format: "%.1f", settings.autospaceDelay)) s"
        delayLabel.alpha = settings.autospace ? 1 : 0.5
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let inset = bounds.insetBy(dx: Theme.Space.l, dy: Theme.Space.s)
        let rowHeight = max(34, (inset.height - 8) / 6)
        var y = inset.minY
        func row(_ label: UILabel, _ control: UIView) {
            label.frame = CGRect(x: inset.minX, y: y, width: inset.width * 0.5, height: rowHeight)
            control.sizeToFit()
            control.frame.origin = CGPoint(x: inset.maxX - control.bounds.width, y: y + (rowHeight - control.bounds.height) / 2)
            y += rowHeight
        }
        title.frame = CGRect(x: inset.minX, y: y, width: inset.width, height: rowHeight)
        y += rowHeight
        row(autospaceLabel, autospaceSwitch)
        delayLabel.frame = CGRect(x: inset.minX, y: y, width: inset.width * 0.35, height: rowHeight)
        delaySlider.frame = CGRect(x: inset.minX + inset.width * 0.38, y: y, width: inset.width * 0.62, height: rowHeight)
        y += rowHeight
        row(trailsLabel, trailsSwitch)
        row(splitLabel, splitSwitch)
        done.sizeToFit()
        done.frame = CGRect(x: inset.maxX - max(96, done.bounds.width), y: y + (rowHeight - 36) / 2, width: max(96, done.bounds.width), height: 36)
    }
}
#endif
