import SwiftUI
import WidgetKit

// The widget extension (com.tinypenguin.astrotype.live). For now it only holds the
// throwaway dictation test's Live Activity (Gabriel, 7 Nov 2026): iOS lets an app record
// in the background only while a Live Activity is showing, and a Live Activity is drawn
// by a widget extension.

@main
struct AstrotypeLiveBundle: WidgetBundle {
    var body: some Widget {
        DictationLiveActivity()
    }
}
