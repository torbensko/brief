import SwiftUI

/// A standalone host for the production recording views, using only preview fixtures.
@main
struct BriefPreviewApp: App {
    var body: some Scene {
        WindowGroup("Brief UI preview") {
            #if DEBUG
            RecordingPreviewPlayground()
            #else
            Text("Select the Debug configuration to review the UI.")
            #endif
        }.windowResizability(.contentSize)
    }
}

#if DEBUG
#Preview("Progress design") {
    RecordingProgressPreview()
}

#Preview("Progress • dark") {
    RecordingProgressPreview(dark: true)
}

#Preview("Interactive review") {
    RecordingPreviewPlayground()
}

#Preview("All states side by side") {
    RecordingPreviewGallery()
}

#Preview("Stacked recordings") {
    RecordingPreviewPlayground(scenario: .stacked)
}

#Preview("Stacked • dark") {
    RecordingPreviewPlayground(scenario: .stacked, dark: true)
}

#endif
