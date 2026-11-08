import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The dictation
// test's Live Activity: what the session is doing, a Talk button (start or stop
// listening) and a Stop button (end the session). Both buttons are LiveActivityIntents,
// so iOS runs them in the app.

struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.listening ? "waveform" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(context.state.listening ? .red : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Astrotype dictation test").font(.headline)
                    Text(context.state.note).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Buttons(listening: context.state.listening)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.listening ? "waveform" : "mic.fill")
                        .foregroundStyle(context.state.listening ? .red : .blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.note).font(.subheadline).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Buttons(listening: context.state.listening)
                }
            } compactLeading: {
                Image(systemName: context.state.listening ? "waveform" : "mic.fill")
                    .foregroundStyle(context.state.listening ? .red : .blue)
            } compactTrailing: {
                Text(context.state.listening ? "On" : "Ready").font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: context.state.listening ? "waveform" : "mic.fill")
                    .foregroundStyle(context.state.listening ? .red : .blue)
            }
        }
    }
}

private struct Buttons: View {
    let listening: Bool

    var body: some View {
        HStack(spacing: 8) {
            if listening {
                Button(intent: DictationDoneIntent()) {
                    Label("Done", systemImage: "stop.fill")
                }
                .tint(.red)
            } else {
                Button(intent: DictationTalkIntent()) {
                    Label("Talk", systemImage: "mic.fill")
                }
                .tint(.blue)
            }
            Button(intent: StopDictationProbeIntent()) {
                Label("End", systemImage: "xmark")
            }
            .tint(.gray)
        }
        .buttonStyle(.borderedProminent)
    }
}
