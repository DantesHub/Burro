import AppKit
import QuartzCore
import SwiftUI
import BurroCore

/// The compositor animates opacity; no timer or per-frame SwiftUI evaluation.
struct RunningPulse: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PulseDot(active: active && !reduceMotion)
            .frame(width: 5, height: 5).accessibilityHidden(true)
    }
}

private struct PulseDot: NSViewRepresentable {
    var active: Bool
    func makeNSView(context: Context) -> PulseDotView { PulseDotView() }
    func updateNSView(_ view: PulseDotView, context: Context) { view.active = active }
}

private final class PulseDotView: NSView {
    var active = false { didSet { updatePulse() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(AgentState.working.color).cgColor
        layer?.cornerRadius = 2.5
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(powerOrVisibilityChanged), name: name, object: nil)
        }
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePulse() }
    @objc nonisolated private func powerOrVisibilityChanged() {
        // Power notifications may be posted off the main thread.
        Task { @MainActor [weak self] in self?.updatePulse() }
    }

    private func updatePulse() {
        guard active, window?.occlusionState.contains(.visible) == true,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            layer?.removeAnimation(forKey: "running.pulse")
            return
        }
        guard layer?.animation(forKey: "running.pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.4; pulse.toValue = 0.9
        pulse.duration = 1; pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "running.pulse")
    }
}
