import CoreGraphics
import XCTest
@testable import IONNativeIslandsLib

final class NIMotionTests: XCTestCase {
    private let pagePush = NIEasing.cubicBezier(0, 0.8, 0.3, 1)

    private func slide(
        from: [Double],
        to end: [Double],
        easing: NIEasing = .linear,
        channel: NIMotionChannel = .translate,
        iterations: Double = 1,
        direction: String = "normal",
        delay: Double = 0,
        sampledTime: Double = 0
    ) -> NIMotionAnimation {
        NIMotionAnimation(
            channel: channel,
            keyframes: [
                NIMotionKeyframe(offset: 0, value: from, easing: easing),
                NIMotionKeyframe(offset: 1, value: end, easing: .linear),
            ],
            delay: delay,
            duration: 400,
            iterations: iterations,
            direction: direction,
            startTime: 1000,
            sampledTime: sampledTime
        )
    }

    func testCubicBeziersMatchTheCurveCSSDraws() {
        XCTAssertEqual(pagePush.apply(0.1), 0.6068953650974688, accuracy: 1e-6)
        XCTAssertEqual(pagePush.apply(0.5), 0.9430190304233406, accuracy: 1e-6)
        let ease = NIEasing.cubicBezier(0.25, 0.1, 0.25, 1)
        XCTAssertEqual(ease.apply(0.5), 0.8024033875848569, accuracy: 1e-6)
        XCTAssertEqual(ease.apply(0.25), 0.40851059135539586, accuracy: 1e-6)
        XCTAssertEqual(ease.apply(0), 0)
        XCTAssertEqual(ease.apply(1), 1)
    }

    func testStepsAndLinearStopsFollowCSSEasing() {
        XCTAssertEqual(NIEasing.steps(4, "end").apply(0.3), 0.25)
        XCTAssertEqual(NIEasing.steps(4, "start").apply(0.3), 0.5)
        XCTAssertEqual(NIEasing.steps(5, "none").apply(0.5), 0.5)
        XCTAssertEqual(NIEasing.steps(3, "both").apply(0.1), 0.25)
        let stops = NIEasing.points(inputs: [0, 0.5, 1], outputs: [0, 0.25, 1])
        XCTAssertEqual(stops.apply(0.75), 0.625, accuracy: 1e-9)
        XCTAssertEqual(stops.apply(0.25), 0.125, accuracy: 1e-9)
    }

    func testAPagePushMovesByHowFarItsTranslationChangedSinceTheLayout() {
        let motion = NIMotion(id: "page", animations: [slide(from: [128, 0], to: [0, 0], easing: pagePush)])
        XCTAssertEqual(motion.offset(at: 1000), .zero)
        XCTAssertEqual(motion.offset(at: 1200).x, -128 * 0.9430190304233406, accuracy: 1e-4)
        XCTAssertEqual(motion.offset(at: 1400).x, -128, accuracy: 1e-9)
        XCTAssertEqual(motion.offset(at: 5000).x, -128, accuracy: 1e-9)
        XCTAssertEqual(motion.offset(at: 900).x, 0, accuracy: 1e-9)
        XCTAssertTrue(motion.runs(after: 1399))
        XCTAssertFalse(motion.runs(after: 1400))
    }

    func testTheModelAtAnyTimeMinusItsTranslationThereIsTheSameRebasedPlace() {
        let motion = NIMotion(id: "page", animations: [slide(from: [0, 0], to: [-80.4, 0], easing: pagePush, sampledTime: 30)])
        let rebased = [1000.0, 1100, 1250, 1400, 1600].map { time -> CGFloat in
            motion.offset(at: time).x - (motion.translation(at: time)?.x ?? .nan)
        }
        for value in rebased { XCTAssertEqual(value, rebased[0], accuracy: 1e-9) }
        var held = motion
        held.held = true
        XCTAssertNil(held.translation(at: 1100))
    }

    func testALayoutMeasuredMidMotionIsMovedFromWhereItWasMeasured() {
        let motion = NIMotion(id: "page", animations: [slide(from: [0, 0], to: [0, -400], sampledTime: 100)])
        XCTAssertEqual(motion.offset(at: 1100).y, 0, accuracy: 1e-9)
        XCTAssertEqual(motion.offset(at: 1200).y, -100, accuracy: 1e-9)
    }

    func testIterationsAndDirectionsRepeatTheKeyframes() {
        let alternate = slide(from: [0, 0], to: [100, 0], iterations: 2, direction: "alternate")
        XCTAssertEqual(alternate.value(at: 100)[0], 25, accuracy: 1e-9)
        XCTAssertEqual(alternate.value(at: 500)[0], 75, accuracy: 1e-9)
        XCTAssertEqual(alternate.value(at: 800)[0], 0, accuracy: 1e-9)
        XCTAssertEqual(slide(from: [0, 0], to: [100, 0], direction: "reverse").value(at: 100)[0], 75, accuracy: 1e-9)
        let forever = slide(from: [0, 0], to: [100, 0], iterations: .infinity)
        XCTAssertEqual(forever.value(at: 4200)[0], 50, accuracy: 1e-9)
        XCTAssertTrue(forever.runs(after: 1.0e8))
        let delayed = slide(from: [0, 0], to: [100, 0], delay: 100)
        XCTAssertEqual(delayed.value(at: 50)[0], 0, accuracy: 1e-9)
        XCTAssertEqual(delayed.value(at: 300)[0], 50, accuracy: 1e-9)
    }

    func testAFadeGivesTheElementsOpacityClamped() {
        let motion = NIMotion(id: "page", animations: [slide(from: [1], to: [0], channel: .opacity)])
        XCTAssertEqual(motion.opacity(at: 1200) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(motion.opacity(at: 9000) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(motion.offset(at: 1200), .zero)
        XCTAssertNil(NIMotion(id: "slide", animations: [slide(from: [0, 0], to: [1, 0])]).opacity(at: 1200))
    }

    func testAHeldMotionStaysWhereTheLayoutMeasuredIt() {
        var motion = NIMotion(
            id: "page",
            animations: [slide(from: [128, 0], to: [0, 0]), slide(from: [1], to: [0], channel: .opacity)]
        )
        motion.held = true
        XCTAssertEqual(motion.offset(at: 1200), .zero)
        XCTAssertEqual(motion.opacity(at: 1200) ?? -1, 1, accuracy: 1e-9)
        motion.held = false
        XCTAssertEqual(motion.offset(at: 1200).x, -64, accuracy: 1e-9)
    }

    func testWebKitsAnimationForAMotionIsFoundByPropertyKeyframesAndDuration() {
        let push = slide(from: [402, 0], to: [0, 0])
        let drawn = NIWebKitAnimation(keyPath: "transform", values: [[402, 0, 0], [0, 0, 0]], duration: 0.4, begin: 5)
        XCTAssertTrue(push.isDrawn(by: drawn))
        XCTAssertFalse(push.isDrawn(by: NIWebKitAnimation(keyPath: "transform", values: [[0, 0, 0], [-80.4, 0, 0]], duration: 0.4, begin: 5)))
        XCTAssertFalse(push.isDrawn(by: NIWebKitAnimation(keyPath: "transform", values: [[402, 0, 0], [0, 0, 0]], duration: 0.2, begin: 5)))
        XCTAssertFalse(push.isDrawn(by: NIWebKitAnimation(keyPath: "opacity", values: [[1], [0]], duration: 0.4, begin: 5)))
        let fade = slide(from: [1], to: [0], channel: .opacity)
        XCTAssertTrue(fade.isDrawn(by: NIWebKitAnimation(keyPath: "opacity", values: [[1], [0]], duration: 0.4, begin: 5)))
    }

    func testThePageClockIsTheSmallestDelaySeen() {
        let clock = NIPageClock()
        XCTAssertNil(clock.pageTime(nativeSeconds: 0))
        clock.sample(pageMilliseconds: 1000, nativeSeconds: 5.003)
        clock.sample(pageMilliseconds: 1010, nativeSeconds: 5.011)
        clock.sample(pageMilliseconds: 1020, nativeSeconds: 5.030)
        XCTAssertEqual(clock.pageTime(nativeSeconds: 5.017) ?? 0, 1016, accuracy: 1e-6)
        clock.clear()
        XCTAssertNil(clock.pageTime(nativeSeconds: 5.017))
    }

    private func payload(easing: Any? = ["bezier": [0, 0.8, 0.3, 1]]) -> [[String: Any]] {
        var first: [String: Any] = ["offset": 0, "value": [128, 0]]
        if let easing { first["easing"] = easing }
        return [[
            "id": "motion-1",
            "animations": [[
                "channel": "translate",
                "keyframes": [first, ["offset": 1, "value": [0, 0]]],
                "delay": 0, "endDelay": 0, "duration": 400, "iterations": 1, "iterationStart": 0,
                "direction": "normal", "fill": "forwards", "startTime": 1000.5, "playbackRate": 1, "sampledTime": 0,
            ]],
        ]]
    }

    func testAMotionPayloadIsCheckedAndRead() {
        let (ids, error) = NIMotionPayload.validate(payload())
        XCTAssertNil(error)
        XCTAssertEqual(ids, ["motion-1"])
        let motion = NIMotionPayload.parse(payload())["motion-1"]
        XCTAssertEqual(motion?.offset(at: 1200.5).x ?? 0, -128 * 0.9430190304233406, accuracy: 1e-4)
        XCTAssertNil(NIMotionPayload.pathError(["motion-1"], ids: ids, label: "component 'a'"))
        XCTAssertEqual(
            NIMotionPayload.pathError(["motion-2"], ids: ids, label: "component 'a'"),
            "component 'a' motionPath references unknown motion 'motion-2'"
        )
        XCTAssertNotNil(NIMotionPayload.validate(payload(easing: ["bezier": [2, 0, 0, 1]])).error)
        XCTAssertNotNil(NIMotionPayload.validate(payload(easing: ["steps": 0, "jump": "end"])).error)
        XCTAssertNotNil(NIMotionPayload.validate(payload(easing: ["bezier": [0, 0, 1, 1], "steps": 2])).error)
        var infinite = payload()
        var animations = infinite[0]["animations"] as? [[String: Any]] ?? []
        animations[0]["iterations"] = NSNull()
        infinite[0]["animations"] = animations
        XCTAssertNil(NIMotionPayload.validate(infinite).error)
        XCTAssertTrue(NIMotionPayload.parse(infinite)["motion-1"]?.runs(after: 1.0e8) ?? false)
    }

    func testATintIsARegionWithACSSColor() {
        let component: [String: Any] = [
            "id": "island", "type": "fixture", "active": true, "interactive": false, "plane": "overlay",
            "coordinateSpace": "document", "scrollPath": [],
            "rect": ["x": 0, "y": 0, "w": 10, "h": 10],
        ]
        func error(_ color: Any) -> String? {
            NILayoutValidation.error(
                components: [component],
                order: ["island"],
                exclusions: [:],
                cutouts: [:],
                tints: ["island": [[
                    "rect": ["x": 0, "y": 0, "w": 10, "h": 10], "coordinateSpace": "document",
                    "scrollPath": [], "color": color,
                ]]]
            )
        }
        XCTAssertNil(error([20, 16, 12, 0.22]))
        XCTAssertEqual(error([20, 16, 12, 1.5]), "tint 0 for 'island' has an invalid color")
        XCTAssertEqual(error([20, 16, 12]), "tint 0 for 'island' has an invalid color")
        XCTAssertEqual(error([256, 16, 12, 0.2]), "tint 0 for 'island' has an invalid color")
        XCTAssertEqual(NITintColor([255, 0, 51, 0.5])?.blue ?? 0, 0.2, accuracy: 1e-9)
    }

    func testALayoutNamingAnUnknownMotionIsRefused() {
        let component: [String: Any] = [
            "id": "island", "type": "fixture", "active": true, "interactive": false, "plane": "overlay",
            "coordinateSpace": "document", "scrollPath": [],
            "rect": ["x": 0, "y": 0, "w": 10, "h": 10], "motionPath": ["motion-9"],
        ]
        XCTAssertEqual(
            NILayoutValidation.error(
                components: [component], order: ["island"], exclusions: [:], cutouts: [:], motions: payload()
            ),
            "component 0 motionPath references unknown motion 'motion-9'"
        )
        var known = component
        known["motionPath"] = ["motion-1"]
        XCTAssertNil(
            NILayoutValidation.error(
                components: [known], order: ["island"], exclusions: [:], cutouts: [:], motions: payload()
            )
        )
    }
}
