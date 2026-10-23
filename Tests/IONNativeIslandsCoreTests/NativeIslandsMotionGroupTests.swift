#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsMotionGroupTests: XCTestCase {
        func testWebKitsOnePassGroupKeepsItsReplayTrack() throws {
            let source = CAKeyframeAnimation(keyPath: "transform")
            source.values = [[160, 0, 0], [0, 0, 0]]
            source.duration = 1.2
            source.repeatCount = 1
            let group = CAAnimationGroup()
            group.animations = [source]
            group.beginTime = 1
            group.duration = .greatestFiniteMagnitude
            group.repeatCount = 1
            let drawn = NIWebKitAnimation(keyPath: "transform", values: [[160, 0, 0], [0, 0, 0]], duration: 1.2, begin: 5)
            let animation = WebKitAnimation(drawn: drawn, source: source, group: group)
            let track = try XCTUnwrap(animation.track)
            XCTAssertEqual(track.beginTime, 5)
            XCTAssertEqual(track.repeatCount, 1)
            group.repeatCount = 2
            XCTAssertNil(animation.track)
            group.repeatCount = 0.5
            XCTAssertNil(animation.track)
        }
    }
#endif
