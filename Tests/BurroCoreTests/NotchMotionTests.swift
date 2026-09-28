// Motion continuity is checked numerically and against actual Core Animation presentation layers.
import XCTest
@testable import BurroCore

final class NotchMotionTests: XCTestCase {
    func testMotionHasIntermediateFramesAndSettlesWithoutOvershoot() {
        var motion = NotchMotion()
        let compact = CGSize(width: 293, height: 34), expanded = CGSize(width: 480, height: 373)
        motion.retarget(size: compact, expanded: false, at: 0, animated: false)
        motion.retarget(size: expanded, expanded: true, at: 1, animated: true)
        let early = motion.sample(at: 1.05), middle = motion.sample(at: 1.12)
        XCTAssertGreaterThan(early.size.height, compact.height + 10)
        XCTAssertLessThan(middle.size.height, expanded.height - 30)
        XCTAssertGreaterThan(middle.size.height, early.size.height)
        for t in stride(from: 1.0, through: 1.5, by: 1.0 / 120) {
            XCTAssertLessThanOrEqual(motion.sample(at: t).size.height, expanded.height)
        }
        XCTAssertEqual(motion.sample(at: 1.5).size, expanded)
    }
    func testRapidRetargetPreservesPositionAndVelocity() {
        var motion = NotchMotion()
        let compact = CGSize(width: 293, height: 34), expanded = CGSize(width: 480, height: 373)
        motion.retarget(size: compact, expanded: false, at: 0, animated: false)
        motion.retarget(size: expanded, expanded: true, at: 1, animated: true)
        for (time, opening) in [(1.07, false), (1.14, true), (1.19, false), (1.24, true)] {
            let before = motion.sample(at: time).size.height
            let velocityBefore = (before - motion.sample(at: time - 0.00001).size.height) / 0.00001
            motion.retarget(size: opening ? expanded : compact, expanded: opening, at: time, animated: true)
            XCTAssertEqual(motion.sample(at: time).size.height, before, accuracy: 0.00001)
            let velocityAfter = (motion.sample(at: time + 0.00001).size.height - before) / 0.00001
            XCTAssertEqual(velocityAfter, velocityBefore, accuracy: 2)
        }
    }
}
