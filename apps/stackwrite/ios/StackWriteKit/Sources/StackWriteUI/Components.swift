#if canImport(UIKit)
import SwiftUI

/// The pill button with a pressable bottom edge (DESIGN.md "Design system").
///
///     Button("Let's go") { ... }.buttonStyle(.primary)
///     Button("Skip for now") { ... }.buttonStyle(.ghost)
public struct PrimaryButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, small, ghost }
    var kind: Kind

    public init(kind: Kind = .primary) { self.kind = kind }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        switch kind {
        case .ghost:
            configuration.label
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.muted)
                .padding(Theme.Space.s)
                .opacity(pressed ? 0.6 : 1)
        case .primary, .small:
            let small = kind == .small
            let edge: CGFloat = small ? 4 : 6
            configuration.label
                .font(small ? .system(.subheadline, design: .rounded, weight: .heavy)
                            : .system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, small ? Theme.Space.l : Theme.Space.gutter)
                .padding(.vertical, small ? 10 : 17)
                .frame(maxWidth: small ? nil : .infinity)
                .background(
                    Capsule().fill(Theme.accent)
                        .shadow(color: .black.opacity(0.25), radius: 0, y: pressed ? edge / 2 : edge)
                )
                .offset(y: pressed ? edge / 2 : 0)
                .scaleEffect(pressed ? 0.98 : 1)
                .animation(Theme.Motion.quickSpring, value: pressed)
        }
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var small: PrimaryButtonStyle { PrimaryButtonStyle(kind: .small) }
    static var ghost: PrimaryButtonStyle { PrimaryButtonStyle(kind: .ghost) }
}

/// A white (or deep water) rounded card.
public struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

/// A card row: a title, an optional subtitle, and something on the right.
public struct Row<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        Card {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded, weight: .bold))
                    if let subtitle {
                        Text(subtitle).font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

public extension Row where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small caps above a group of rows.
public struct SectionLabel: View {
    var text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded, weight: .black))
            .tracking(0.8)
            .foregroundStyle(Theme.muted)
            .padding(.leading, Theme.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small ice pill, like "Best 47 wpm" or "On".
public struct Chip: View {
    var text: String
    var tint: Color?

    public init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .heavy))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(tint ?? Theme.ice))
            .foregroundStyle(tint == nil ? Theme.ink : .white)
    }
}

/// The yellow PRO tag.
public struct ProBadge: View {
    public init() {}

    public var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(0.8)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.sun))
            .foregroundStyle(Theme.sunInk)
            .accessibilityLabel("Pro")
    }
}
#endif
