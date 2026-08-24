import XCTest
@testable import IONNativeIslandsLib

final class NIWeakReferenceRegistryTests: XCTestCase {
    func testRegisteredSceneCanBeReplacedAndRemoved() {
        let registry = NIWeakReferenceRegistry<NSObject, NSObject>()
        let key = NSObject()
        let first = NSObject()
        let second = NSObject()

        registry.set(first, for: key)
        XCTAssertTrue(registry.value(for: key) === first)

        registry.set(second, for: key)
        XCTAssertTrue(registry.value(for: key) === second)

        registry.removeValue(for: key)
        XCTAssertNil(registry.value(for: key))
    }
}
