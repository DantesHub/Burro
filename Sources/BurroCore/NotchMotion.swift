// Continuous critically damped motion, sampled into compositor keyframes without per-frame UI work.
import Foundation
import CoreGraphics

public struct NotchSpring: Sendable {
    public var origin: Double
    public var velocity: Double
    public var target: Double
    public var frequency: Double

    public func sample(after time: TimeInterval) -> (value: Double, velocity: Double) {
        let t = max(0, time), displacement = origin - target
        let coefficient = velocity + frequency * displacement
        let decay = exp(-frequency * t)
        return (target + (displacement + coefficient * t) * decay,
                (velocity - frequency * coefficient * t) * decay)
    }
}

public struct NotchMotion: Sendable {
    public struct Sample: Sendable {
        public var size: CGSize
        public var expansion: Double
    }
    private var width = NotchSpring(origin: 108, velocity: 0, target: 108, frequency: 25)
    private var height = NotchSpring(origin: 26, velocity: 0, target: 26, frequency: 25)
    private var expansion = NotchSpring(origin: 0, velocity: 0, target: 0, frequency: 25)
    public private(set) var startedAt: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public init() {}

    public mutating func retarget(size: CGSize, expanded: Bool, at time: TimeInterval, animated: Bool) {
        let elapsed = time - startedAt
        let frequency = expanded ? 25.0 : 28.0
        func next(_ old: NotchSpring, _ target: Double) -> NotchSpring {
            let current = elapsed >= duration ? (value: old.target, velocity: 0.0) : old.sample(after: elapsed)
            return NotchSpring(origin: animated ? current.value : target,
                               velocity: animated ? current.velocity : 0, target: target, frequency: frequency)
        }
        width = next(width, size.width); height = next(height, size.height)
        expansion = next(expansion, expanded ? 1 : 0)
        startedAt = time; duration = animated ? (expanded ? 0.44 : 0.40) : 0
    }
    public func sample(at time: TimeInterval) -> Sample {
        let elapsed = time - startedAt
        if elapsed >= duration { return Sample(size: CGSize(width: width.target, height: height.target), expansion: expansion.target) }
        return Sample(size: CGSize(width: width.sample(after: elapsed).value, height: height.sample(after: elapsed).value),
                      expansion: min(1, max(0, expansion.sample(after: elapsed).value)))
    }
}

// Global screen coordinates keep hover intent independent of native view/window tracking churn.
public enum NotchHoverRegion {
    public static func contains(_ point: CGPoint, compact: CGRect, expanded: CGRect,
                                isExpanded: Bool) -> Bool {
        // Opening requires the compact island itself. Exit tolerance is only for an
        // already-open panel; its fading footprint must never reopen it during collapse.
        let area = isExpanded ? expanded.insetBy(dx: -10, dy: -10) : compact
        // Include the physical top edge; CGRect.contains excludes its maximum coordinates.
        return point.x >= area.minX && point.x <= area.maxX && point.y >= area.minY && point.y <= min(compact.maxY, area.maxY)
    }
}
