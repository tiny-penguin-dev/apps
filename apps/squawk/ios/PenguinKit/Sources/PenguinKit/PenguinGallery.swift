import SwiftUI

/// Every mood and outfit on one screen, for checking the penguin on a real phone.
/// Apps can show it from a hidden debug menu.
public struct PenguinGallery: View {
    public var style: PenguinStyle

    public init(style: PenguinStyle = .squawk) {
        self.style = style
    }

    @State private var accessory: PenguinAccessory?
    @State private var waving = false
    @State private var animated = true

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Outfit", selection: $accessory) {
                    Text("None").tag(PenguinAccessory?.none)
                    ForEach(PenguinAccessory.allCases) { item in
                        Text(item.displayName).tag(PenguinAccessory?.some(item))
                    }
                }
                Toggle("Wave", isOn: $waving)
                Toggle("Animate", isOn: $animated)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(PenguinMood.allCases) { mood in
                        VStack(spacing: 6) {
                            PenguinView(mood: mood, style: style, accessory: accessory, waving: waving, animated: animated)
                                .frame(height: 150)
                            Text(mood.displayName).font(.system(.subheadline, design: .rounded, weight: .bold))
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }

                Text("Sizes").font(.system(.headline, design: .rounded))
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach([24.0, 44, 64, 96, 128], id: \.self) { size in
                        PenguinView(mood: .awake, style: style, accessory: accessory, animated: animated)
                            .frame(width: size, height: size)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Penguin")
    }
}

#Preview {
    NavigationStack { PenguinGallery() }
}
