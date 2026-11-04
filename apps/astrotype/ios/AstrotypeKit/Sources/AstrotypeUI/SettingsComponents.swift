#if canImport(UIKit)
import SwiftUI

// The pieces Settings is built from (features/settings/FEATURE.md, "Design system").
// A page is section labels, groups of rows and footnotes:
//
//     SectionLabel("Gestures")
//     SettingsGroup {
//         SettingsToggle("Slide on space", subtitle: "Move the cursor",
//                        symbol: "arrow.left.and.right", tint: Theme.left, isOn: $slide)
//         SettingsLink("Learned words", symbol: "book.closed", tint: Theme.mint, value: "214") { open() }
//     }
//     GroupFootnote("At 100% every key sits where Apple's does.")

/// One card holding several rows, with a hairline between them. Replaces one card per
/// row, so a page reads as a few groups instead of a long list.
public struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.displayScale) private var displayScale

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle().fill(Theme.line).frame(height: 1 / displayScale)
                    }
                    row
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .foregroundStyle(Theme.ink)
    }
}

/// A small rounded square with an SF Symbol, coloured by what the row is about: teal
/// for typing, coral for the right-thumb things, mint for your words, sun for Pro,
/// slate for system rows, ice for quiet ones. Decorative: the row's title is its label.
public struct IconTile: View {
    var symbol: String
    var tint: Color
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    public init(_ symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .bold))
            .foregroundStyle(tint == Theme.sun ? Theme.sunInk : tint == Theme.ice ? Theme.ink : .white)
            .frame(width: side, height: side)
            .background(tint, in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row inside a `SettingsGroup`: an optional icon, a title, an optional subtitle and
/// something on the right. At the accessibility text sizes the something moves under
/// the text, so nothing squeezes.
public struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color
    var titleColor: Color
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Theme.accent,
                titleColor: Color = Theme.ink, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.titleColor = titleColor
        self.trailing = trailing()
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.m) { icon; text }
                    trailing
                }
            } else {
                HStack(spacing: Theme.Space.m) { icon; text; trailing }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if let symbol { IconTile(symbol, tint: tint) }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.body, design: .rounded, weight: .bold)).foregroundStyle(titleColor)
            if let subtitle {
                Text(subtitle).font(.sw(.small)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Theme.accent, titleColor: Color = Theme.ink) {
        self.init(title, subtitle: subtitle, symbol: symbol, tint: tint, titleColor: titleColor) { EmptyView() }
    }
}

/// A row with a switch on the right. VoiceOver reads it as one switch.
public struct SettingsToggle: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color
    @Binding var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Theme.accent, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self._isOn = isOn
    }

    public var body: some View {
        SettingsRow(title, subtitle: subtitle, symbol: symbol, tint: tint) {
            Toggle(title, isOn: $isOn).labelsHidden().tint(Theme.mint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row that opens something: a page, a list, a sheet. A value (a count, a state) can
/// sit before the chevron.
public struct SettingsLink: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color
    var value: String?
    var selected: Bool
    var action: () -> Void

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Theme.accent,
                value: String? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.value = value
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SettingsRow(title, subtitle: subtitle, symbol: symbol, tint: tint) {
                HStack(spacing: Theme.Space.s) {
                    if let value {
                        Text(value).font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted).monospacedDigit()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, design: .rounded, weight: .black))
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
            }
            // Rounded like the group, which no longer clips its rows.
            .background(selected ? Theme.accent.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(SettingsPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row that only shows a value on the right, like a reading on the Debug page. The
/// value can take a colour to say it is high (`Theme.sun`) or over (`Theme.danger`).
/// VoiceOver reads the title, subtitle and value as one.
public struct SettingsValue: View {
    var title: String
    var subtitle: String?
    var value: String
    var valueColor: Color

    public init(_ title: String, subtitle: String? = nil, value: String, valueColor: Color = Theme.muted) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Text(value).font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(valueColor).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slider row: an optional title with the value on the right, then the slider between
/// two end labels. Without a title it indents under the row above (autospace's wait).
public struct SettingsSlider: View {
    var title: String?
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var low: String
    var high: String
    var valueText: String
    var spokenValue: String
    var accessibilityLabel: String

    public init(_ title: String?, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                low: String, high: String, valueText: String, spokenValue: String? = nil, accessibilityLabel: String? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.low = low
        self.high = high
        self.valueText = valueText
        self.spokenValue = spokenValue ?? valueText
        self.accessibilityLabel = accessibilityLabel ?? title ?? ""
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(.body, design: .rounded, weight: .bold))
                    Spacer()
                    Text(valueText).font(.system(.body, design: .rounded, weight: .black)).monospacedDigit()
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: Theme.Space.m) {
                Text(low).font(.sw(.small)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                Slider(value: $value, in: range, step: step)
                    .tint(Theme.accent)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(spokenValue)
                Text(high).font(.sw(.small)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                if title == nil {
                    Text(valueText).font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit().accessibilityHidden(true)
                }
            }
        }
        .padding(.leading, title == nil ? 56 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
    }
}

/// A short note under a group: the longer "why" that used to fill every subtitle.
public struct GroupFootnote: View {
    var text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).font(.sw(.small)).foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tile at the top of Settings: what it is, and a dot with its state (mint when all
/// is well, sun when it wants a look).
public struct StatusTile: View {
    var title: String
    var status: String
    var ok: Bool
    var action: () -> Void

    public init(_ title: String, status: String, ok: Bool, action: @escaping () -> Void) {
        self.title = title
        self.status = status
        self.ok = ok
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Theme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(ok ? Theme.mint : Theme.sun).frame(width: 8, height: 8)
                    Text(status).font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(SettingsPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// The keyboard at the chosen height, with or without the guesses bar, so the height
/// slider shows what it does. Keys spring to the new height as the slider moves.
public struct KeyboardPreview: View {
    var heightScale: CGFloat
    var showsBar: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(heightScale: CGFloat, showsBar: Bool) {
        self.heightScale = heightScale
        self.showsBar = showsBar
    }

    public var body: some View {
        let keyHeight = 22 * heightScale
        VStack(spacing: 4) {
            if showsBar {
                HStack(spacing: 4) {
                    Color.clear
                    RoundedRectangle(cornerRadius: 5).fill(Theme.card)
                    Color.clear
                }
                .frame(height: 12)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            }
            row(10, height: keyHeight)
            row(9, height: keyHeight).padding(.horizontal, 10)
            HStack(spacing: 3) {
                key(Theme.keyDark, height: keyHeight).frame(maxWidth: 34)
                ForEach(0..<7, id: \.self) { _ in key(Theme.key, height: keyHeight) }
                key(Theme.keyDark, height: keyHeight).frame(maxWidth: 34)
            }
            HStack(spacing: 3) {
                key(Theme.keyDark, height: keyHeight).frame(maxWidth: 34)
                key(Theme.keyDark, height: keyHeight).frame(maxWidth: 34)
                key(Theme.key, height: keyHeight).frame(maxWidth: .infinity)
                key(Theme.keyDark, height: keyHeight).frame(maxWidth: 60)
            }
        }
        .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 8)
        .frame(maxWidth: 300)
        .background(Theme.kb, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(Theme.Motion.spring(reduceMotion: reduceMotion), value: heightScale)
        .animation(Theme.Motion.spring(reduceMotion: reduceMotion), value: showsBar)
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Theme.bg)
        .accessibilityElement()
        .accessibilityLabel("Keyboard at \(Int((heightScale * 100).rounded()))%")
    }

    private func row(_ count: Int, height: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in key(Theme.key, height: height) }
        }
    }

    private func key(_ fill: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill)
            .frame(maxWidth: 24).frame(height: height)
            .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
    }
}

/// A light press for rows and tiles: they dim a little, no bounce.
struct SettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.line.opacity(0.5) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .contentShape(Rectangle())
    }
}

#Preview("Settings pieces") {
    @Previewable @State var on = true
    @Previewable @State var height = 1.0
    ScrollView {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                StatusTile("Keyboard", status: "On", ok: true) {}
                StatusTile("Pro trial", status: "11 days left", ok: false) {}
            }
            .fixedSize(horizontal: false, vertical: true)
            SectionLabel("Size")
            SettingsGroup {
                KeyboardPreview(heightScale: height, showsBar: on)
                SettingsSlider("Height", value: $height, in: 0.8...1.2, step: 0.05, low: "Shorter", high: "Taller",
                               valueText: "\(Int((height * 100).rounded()))%")
                SettingsToggle("Guesses bar", subtitle: "Above the keys on a phone", symbol: "rectangle.topthird.inset.filled",
                               tint: Theme.left, isOn: $on)
                SettingsLink("Learned words", symbol: "book.closed", tint: Theme.mint, value: "214") {}
                Button {} label: { SettingsRow("Forget what it learned", titleColor: Theme.danger) }
            }
            GroupFootnote("At 100% every key sits where Apple's does.")
        }
        .padding(Theme.Space.gutter)
    }
    .background(Theme.bg)
}
#endif
