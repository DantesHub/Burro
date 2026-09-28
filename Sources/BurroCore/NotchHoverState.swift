// Deterministic hover intent, explicit pinning, and dismissal suppression for the notch.
import Foundation

public struct NotchHoverState: Sendable {
    public private(set) var expanded = false
    public private(set) var pinned = false
    public private(set) var pointerInside = false
    public private(set) var deadline: TimeInterval?
    private var suppressedUntilExit = false
    public init() {}

    public mutating func updatePointer(inside: Bool, now: TimeInterval) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if !inside { suppressedUntilExit = false }
        deadline = nil
        guard !pinned else { return }
        if inside && !expanded && !suppressedUntilExit { expanded = true }
        if !inside && expanded { deadline = now + 0.12 }
    }
    public mutating func advance(now: TimeInterval) {
        guard let deadline, now >= deadline else { return }
        self.deadline = nil
        guard !pinned, !suppressedUntilExit else { return }
        expanded = pointerInside
    }
    public mutating func show(pointerInside: Bool) {
        self.pointerInside = pointerInside
        expanded = true
        pinned = false
        suppressedUntilExit = false
        deadline = nil
    }
    public mutating func dismiss(pointerInside: Bool) {
        self.pointerInside = pointerInside
        expanded = false
        pinned = false
        suppressedUntilExit = pointerInside
        deadline = nil
    }
    public mutating func togglePin(now: TimeInterval) {
        pinned.toggle()
        deadline = nil
        if pinned { expanded = true }
        else if !pointerInside && expanded { deadline = now + 0.12 }
    }
}
