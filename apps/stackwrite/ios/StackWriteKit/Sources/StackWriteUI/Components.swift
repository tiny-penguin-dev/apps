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

/// A round number or tick, as on setup steps and drills.
public struct NumberBadge: View {
    public enum Mark: Sendable, Equatable { case number(Int), done }
    var mark: Mark

    public init(_ mark: Mark) { self.mark = mark }

    public var body: some View {
        ZStack {
            Circle().fill(mark == .done ? Theme.mint : Theme.ice)
            switch mark {
            case .number(let n):
                Text("\(n)").font(.system(.body, design: .rounded, weight: .black)).foregroundStyle(Theme.ink)
            case .done:
                Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

/// A numbered setup step: "1  Open Settings › General › Keyboard".
public struct StepRow: View {
    var number: Int
    var text: Text

    public init(_ number: Int, text: Text) {
        self.number = number
        self.text = text
    }

    public var body: some View {
        Card {
            HStack(spacing: Theme.Space.m) {
                NumberBadge(.number(number))
                text.font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
    }
}

/// You versus Apple's keyboard: a track filled with the two thumb colours.
public struct Meter: View {
    var leading: String
    var trailing: String
    /// 0 to 1.
    var fraction: Double

    public init(leading: String, trailing: String, fraction: Double) {
        self.leading = leading
        self.trailing = trailing
        self.fraction = fraction
    }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(leading).font(.sw(.small)).foregroundStyle(Theme.muted)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(LinearGradient(colors: [Theme.left, Theme.right], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 12)
            Text(trailing).font(.sw(.small)).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven dots for the week, ticked on practised days.
public struct WeekDots: View {
    public struct Day: Identifiable, Sendable {
        public var id: String
        public var letter: String
        public var done: Bool
        public var isToday: Bool

        public init(id: String, letter: String, done: Bool, isToday: Bool) {
            self.id = id
            self.letter = letter
            self.done = done
            self.isToday = isToday
        }
    }

    var days: [Day]

    public init(days: [Day]) { self.days = days }

    public var body: some View {
        Card {
            HStack {
                ForEach(days) { day in
                    VStack(spacing: Theme.Space.s) {
                        ZStack {
                            Circle().fill(day.done ? Theme.mint : Theme.line)
                            if day.done {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: day.isToday && !day.done ? 2 : 0))
                        Text(day.letter).font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: practised \(days.filter(\.done).count) of 7 days")
    }
}

/// The sun-yellow banner on Home when the keyboard is not on yet.
public struct Banner: View {
    var text: String
    var action: String
    var onAction: () -> Void

    public init(_ text: String, action: String, onAction: @escaping () -> Void) {
        self.text = text
        self.action = action
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(text).font(.system(.body, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action, action: onAction)
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, 10)
                .background(Capsule().fill(Theme.sunInk))
        }
        .foregroundStyle(Theme.sunInk)
        .padding(Theme.Space.l)
        .background(Theme.sun, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

/// A burst of the four colours, for a new best and the keyboard first turning on.
/// Nothing under Reduce Motion.
public struct Confetti: View {
    @State private var fallen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let spin: Double
        let color: Color
        let size: CGFloat
    }

    private static let pieces: [Piece] = (0..<36).map { i in
        let colors = [Theme.left, Theme.right, Theme.sun, Theme.mint]
        return Piece(id: i, x: CGFloat((i * 37) % 100) / 100, delay: Double((i * 13) % 10) / 20,
                     spin: Double((i * 71) % 360), color: colors[i % 4], size: CGFloat(8 + (i * 7) % 7))
    }

    public var body: some View {
        GeometryReader { proxy in
            if !reduceMotion {
                ForEach(Self.pieces) { piece in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 0.6)
                        .rotationEffect(.degrees(fallen ? piece.spin + 540 : piece.spin))
                        .position(x: piece.x * proxy.size.width, y: fallen ? proxy.size.height + 30 : -30)
                        .opacity(fallen ? 0 : 1)
                        .animation(.easeIn(duration: 1.6).delay(piece.delay), value: fallen)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { fallen = true }
    }
}
#endif
