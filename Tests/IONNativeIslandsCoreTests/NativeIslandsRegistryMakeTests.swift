#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import IONNativeIslandsLib

    final class NativeIslandsRegistryMakeTests: XCTestCase {
        private final class Cell: NativeIsland {
            let view = UIView()
        }

        private struct Refusal: Error {}

        func testAHostMakesARegisteredComponentsIsland() {
            NativeIslandsRegistry.register(componentName: "fixture.makeCell") { Cell() }
            XCTAssertTrue(NativeIslandsRegistry.make(componentName: "fixture.makeCell") is Cell)
            XCTAssertFalse(
                NativeIslandsRegistry.make(componentName: "fixture.makeCell")
                    === NativeIslandsRegistry.make(componentName: "fixture.makeCell")
            )
        }

        func testAnUnknownOrFailingComponentMakesNothing() {
            XCTAssertNil(NativeIslandsRegistry.make(componentName: "fixture.neverRegistered"))
            NativeIslandsRegistry.register(componentName: "fixture.makeRefuses") { throw Refusal() }
            XCTAssertNil(NativeIslandsRegistry.make(componentName: "fixture.makeRefuses"))
        }
    }
#endif
