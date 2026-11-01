import AVFoundation
import SquawkKit
import SwiftUI

/// Pick a sound. Tapping one plays a few seconds of it; tapping a Pro sound without Pro
/// opens the Pro screen.
struct SoundPicker: View {
    @Binding var soundID: String
    @Environment(ProModel.self) private var pro
    @State private var player: AVAudioPlayer?
    @State private var paywall: ProFeature?

    var body: some View {
        List(AlarmSound.all) { sound in
            let allowed = pro.access.allows(sound: sound)
            Button {
                if allowed {
                    soundID = sound.id
                    play(sound)
                } else {
                    paywall = .allSounds
                }
            } label: {
                HStack(spacing: 8) {
                    Text(sound.name).font(Theme.body).foregroundStyle(Theme.ink)
                    if !allowed { ProBadge() }
                    Spacer()
                    if sound.id == soundID {
                        Image(systemName: "checkmark").font(.body.weight(.heavy)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .accessibilityAddTraits(sound.id == soundID ? .isSelected : [])
        }
        .navigationTitle("Sound")
        .onDisappear { player?.stop() }
        .proSheet($paywall)
    }

    private func play(_ sound: AlarmSound) {
        player?.stop()
        guard let url = Bundle.main.url(forResource: sound.id, withExtension: "mp3") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
