import XCTest
@testable import IONNativeIslandsCore

final class NIPersistentTypeRegistryTests: XCTestCase {
    func testMissingAndNilTypesAreNotPersistent() {
        let registry = NIPersistentTypeRegistry()
        XCTAssertFalse(registry.contains(nil))
        XCTAssertFalse(registry.contains("engine"))
    }

    func testRegistrationSurvivesIndependentConsumers() {
        let registry = NIPersistentTypeRegistry()
        registry.register("engine")

        func anotherPluginInstanceReadsRegistry() -> Bool {
            registry.contains("engine")
        }

        XCTAssertTrue(anotherPluginInstanceReadsRegistry())
    }

    func testRegistrationIsIdempotent() {
        let registry = NIPersistentTypeRegistry()
        registry.register("engine")
        registry.register("engine")
        XCTAssertTrue(registry.contains("engine"))
        XCTAssertFalse(registry.contains("other"))
    }
}
