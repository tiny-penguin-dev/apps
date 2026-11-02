import Foundation

/// The tuning pass (features/smart-matching Phase D): a coordinate search over the
/// matcher's weights against the harness. Each round tries each weight scaled up and
/// down, the others held, and keeps whatever raises the first-guess rate (top three
/// breaks ties). The path weight stays at 1 as the scale the others are measured in.
///
///     let steps = Tuning.search(items, language: english)
///     steps.last!.weights     // the best found; steps[0] is where it started
public enum Tuning {
    public struct Step: Sendable, Equatable {
        public var weights: Matcher.Weights
        public var firstGuessRate: Double
        public var topThreeRate: Double
        public var words: Int

        var score: Double { firstGuessRate + topThreeRate / 1000 }

        public var line: String {
            String(format: "first %.2f%% · top three %.2f%% · %@", firstGuessRate * 100, topThreeRate * 100, weights.description)
        }
    }

    public static func evaluate(_ items: [Replay.Item], language: Language, weights: Matcher.Weights) -> Step {
        let report = Replay.report(items, language: language, weights: weights)
        return Step(weights: weights, firstGuessRate: report.firstGuessRate, topThreeRate: report.topThreeRate, words: report.wordCount)
    }

    /// Every improvement in order, starting with `start` as it scores.
    public static func search(_ items: [Replay.Item], language: Language, start: Matcher.Weights = Matcher.Weights(),
                              factors: [Double] = [0.5, 0.75, 1.35, 2], rounds: Int = 2) -> [Step] {
        var best = evaluate(items, language: language, weights: start)
        var steps = [best]
        let knobs: [WritableKeyPath<Matcher.Weights, Double>] = [\.prior, \.context, \.length, \.near, \.standIn]
        for _ in 0..<max(1, rounds) {
            var improved = false
            for knob in knobs {
                for factor in factors {
                    var weights = best.weights
                    weights[keyPath: knob] = (weights[keyPath: knob] * factor * 1000).rounded() / 1000
                    let step = evaluate(items, language: language, weights: weights)
                    if step.score > best.score + 1e-9 {
                        best = step
                        steps.append(step)
                        improved = true
                    }
                }
            }
            if !improved { break }
        }
        return steps
    }
}
