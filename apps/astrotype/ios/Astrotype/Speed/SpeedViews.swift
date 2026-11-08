import AstrotypeCore
import AstrotypeUI
import Charts
import SwiftUI

// features/typing-speed: the everyday speed on Home (`SpeedCard`), its history
// (`SpeedHistoryView`) and the graph both draw (`SpeedChart`): everyday typing as a teal
// line, practice as coral dots.

/// The graph: everyday speed per day (a week per point for a year), practice as dots.
/// Days without enough typing are gaps, never zero.
struct SpeedChart: View {
    var points: [SpeedPoint]
    var unit: Calendar.Component = .day
    /// Small, no axes (Home, the result screen).
    var compact = false
    @Binding var selected: Date?

    init(points: [SpeedPoint], unit: Calendar.Component = .day, compact: Bool = false, selected: Binding<Date?> = .constant(nil)) {
        self.points = points
        self.unit = unit
        self.compact = compact
        _selected = selected
    }

    var body: some View {
        Chart {
            ForEach(segments.indices, id: \.self) { index in
                ForEach(segments[index]) { point in
                    if let speed = point.everyday {
                        LineMark(x: .value("Day", point.date, unit: unit), y: .value("Words per minute", speed),
                                 series: .value("Stretch", index))
                            .foregroundStyle(Theme.left)
                            .lineStyle(StrokeStyle(lineWidth: compact ? 2.5 : 3.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", point.date, unit: unit), y: .value("Words per minute", speed))
                            .foregroundStyle(Theme.left)
                            .symbolSize(compact ? 8 : 18)
                    }
                }
            }
            ForEach(points) { point in
                if let practice = point.practice {
                    PointMark(x: .value("Day", point.date, unit: unit), y: .value("Words per minute", practice))
                        .foregroundStyle(Theme.right)
                        .symbolSize(compact ? 30 : 70)
                }
            }
            if let selected, !compact {
                RuleMark(x: .value("Day", selected, unit: unit))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
        .chartLegend(.hidden)
        .chartXSelection(value: $selected)
        .accessibilityLabel(summary)
    }

    /// The days with a speed, split at the gaps so the line breaks there.
    private var segments: [[SpeedPoint]] {
        var out: [[SpeedPoint]] = []
        var current: [SpeedPoint] = []
        for point in points {
            if point.everyday == nil {
                if !current.isEmpty { out.append(current); current = [] }
            } else {
                current.append(point)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private var summary: String {
        let speeds = points.compactMap(\.everyday)
        guard let last = speeds.last else { return "No typing speed yet" }
        return "Everyday speed, \(speeds.count) points, latest \(Int(last.rounded())) words per minute"
    }
}

/// The legend under a graph.
struct SpeedLegend: View {
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            dot(Theme.left, "Everyday")
            dot(Theme.right, "Practice")
        }
        .font(.system(.caption, design: .rounded, weight: .heavy))
        .foregroundStyle(Theme.muted)
    }

    private func dot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}

/// Home's lead card: the everyday speed, the last 30 days, and Practice for speed.
struct SpeedCard: View {
    var model: AppModel
    var open: () -> Void
    var practice: () -> Void
    var drills: () -> Void
    var turnOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let speed = model.everydaySpeed {
                Button(action: open) { card(speed: speed) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens your speed history")
            } else {
                Card { waiting }
            }
            HStack(spacing: Theme.Space.m) {
                Button("Practice for speed", action: practice).buttonStyle(.small)
                Button("Practice", action: drills).buttonStyle(.ghost)
                Spacer(minLength: 0)
                if let best = model.bestWordsPerMinute {
                    Chip("Best \(best)").accessibilityLabel("Best practice \(best) words per minute")
                }
            }
        }
    }

    private func card(speed: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("Your speed").font(.sw(.heading))
                    Spacer()
                    if let change = model.speedWeekChange, change != 0 {
                        Chip(change > 0 ? "▲ \(change) this week" : "▼ \(-change) this week",
                             tint: change > 0 ? Theme.mint : Theme.slate)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                    Text("\(speed)").bigNumberFont()
                    Text("words per minute,\neveryday typing")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                SpeedChart(points: model.speedPoints(.month), compact: true)
                    .frame(height: 64)
                    .allowsHitTesting(false)
                HStack {
                    SpeedLegend()
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// No speed yet: why, and what to do.
    @ViewBuilder private var waiting: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Your speed").font(.sw(.heading))
                Spacer()
                if model.isFullAccessOn, model.keyboardSettings.measuresSpeed {
                    Chip("Day \(min(model.speedDays + 1, SpeedRules.minEverydayDays)) of \(SpeedRules.minEverydayDays)")
                }
            }
            if !model.isFullAccessOn {
                Text("Turn on Full Access and Astrotype measures how fast you type everywhere, not just here. Only counts and times, never what you type.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn on ›", action: turnOn).buttonStyle(.ghost)
            } else if !model.keyboardSettings.measuresSpeed {
                Text("Measuring your speed is off in Settings → Privacy and sharing.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
            } else {
                Text("Type as you normally do. After three days with a few longer messages, your everyday speed shows up here.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Your speed: the number for the range, the graph, a tapped day's numbers, the
/// tiles, Practice for speed, and how it is counted.
struct SpeedHistoryView: View {
    var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var range: SpeedRange = .week
    @State private var selected: Date?

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Your speed").font(.sw(.title)).padding(.top, Theme.Space.s)
                    let summary = model.speedSummary(range)
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                        Text(summary.speed.map(String.init) ?? "–").bigNumberFont()
                        Text("words per minute\n\(rangeName)")
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        if let change = model.speedWeekChange, change != 0 {
                            Chip(change > 0 ? "▲ \(change)" : "▼ \(-change)", tint: change > 0 ? Theme.mint : Theme.slate)
                                .accessibilityLabel("\(change > 0 ? "Up" : "Down") \(abs(change)) this week")
                        }
                    }
                    Picker("Range", selection: $range) {
                        Text("Week").tag(SpeedRange.week)
                        Text("Month").tag(SpeedRange.month)
                        Text("Year").tag(SpeedRange.year)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: range) { selected = nil }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SpeedChart(points: points, unit: range == .year ? .weekOfYear : .day, selected: $selected)
                                .frame(height: 200)
                            SpeedLegend()
                        }
                    }
                    detail
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: wide ? 4 : 2),
                              spacing: Theme.Space.s) {
                        tile(summary.speed.map(String.init) ?? "–", "Everyday")
                        tile(summary.bestPractice.map(String.init) ?? "–", "Best practice")
                        tile(summary.fastest.map(String.init) ?? "–", "Fastest run")
                        tile(summary.words >= 10_000 ? "\(summary.words / 1000)k" : summary.words.formatted(), "Words counted")
                    }
                    if let best = model.bestWordsPerMinute, let apple = model.appleWordsPerMinute {
                        Meter(leading: "Apple \(apple)", trailing: "You \(best)",
                              fraction: Double(best) / Double(max(best, apple, 1)))
                    }
                    Button("Practice for speed") { path.append(.speedTest(.astrotype, nil)) }
                        .buttonStyle(.primary)
                    Text("Counted whenever you type with Astrotype, in any app. A run counts once it has 10 words without a 5-second pause, so quick replies don't drag it down, and each day is the middle run (the median), so one odd run can't swing it. Passwords and private fields are never counted. Only counts and times are kept, on this iPhone.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Privacy and sharing ›") { path.append(.settingsPage(.privacy)) }
                        .buttonStyle(.ghost)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: wide ? 900 : 560)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            model.refreshSpeed()
            model.speedOpened()
        }
    }

    private var points: [SpeedPoint] { model.speedPoints(range) }

    private var rangeName: String {
        switch range {
        case .week: "last 7 days"
        case .month: "last 30 days"
        case .year: "last 12 months"
        }
    }

    /// The tapped day's (or week's) numbers.
    @ViewBuilder private var detail: some View {
        let calendar = Calendar.current
        let unit: Calendar.Component = range == .year ? .weekOfYear : .day
        if let selected, let point = points.first(where: { calendar.isDate($0.date, equalTo: selected, toGranularity: unit) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(range == .year ? "Week of \(point.date.formatted(.dateTime.month().day()))"
                                    : point.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Text(line(for: point)).font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            Text("Tap the graph for a day's numbers.")
                .font(.sw(.small)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
    }

    private func line(for point: SpeedPoint) -> String {
        var parts: [String] = []
        if let speed = point.everyday {
            parts.append("\(Int(speed.rounded())) wpm everyday · \(point.runs) runs · \(point.words.formatted()) words")
        } else {
            parts.append("Not enough typing to count")
        }
        if let practice = point.practice { parts.append("Practice \(practice) wpm") }
        return parts.joined(separator: "\n")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title2, design: .rounded, weight: .black)).monospacedDigit()
            Text(label).font(.system(.caption, design: .rounded, weight: .heavy)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
