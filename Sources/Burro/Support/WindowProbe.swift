// Hand the dashboard's actual window to the notch controller so agent clicks reuse it.
import SwiftUI
import AppKit

struct WindowProbe: NSViewRepresentable {
    var onAttach: (NSWindow) -> Void
    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView(); view.onAttach = onAttach; return view
    }
    func updateNSView(_ nsView: ProbeView, context: Context) { nsView.onAttach = onAttach }
    final class ProbeView: NSView {
        var onAttach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onAttach?(window) }
        }
    }
}
