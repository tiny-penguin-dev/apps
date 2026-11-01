import AVFoundation
import SquawkKit
import SwiftUI

/// Pick a sound. Tapping one plays a few seconds of it.
struct SoundPicker: View {
    @Binding var soundID: String
    @State private var player: AVAudioPlayer?

    var body: some View {
        List(AlarmSound.all) { sound in
            Button {
                soundID = sound.id
                play(sound)
            } label: {
                HStack {
                    Text(sound.name).font(Theme.body).foregroundStyle(Theme.ink)
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
    }

    private func play(_ sound: AlarmSound) {
        player?.stop()
        guard let url = Bundle.main.url(forResource: sound.id, withExtension: "mp3") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
