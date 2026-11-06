import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? "Type Shortcut…" : (hotKey?.displayString ?? "None")) {
                isRecording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 110)
            if hotKey != nil, !isRecording {
                Button { hotKey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Clear Shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        HotKeyService.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let bare = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if bare, event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
            } else if bare, event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                hotKey = nil
                stopRecording()
            } else if let recorded = HotKey(event: event) {
                hotKey = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyService.shared.isSuspended = false
    }
}
