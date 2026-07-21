import XCTest
@testable import IONNativeIslandsLib

final class NIIslandFactoryRegistryTests: XCTestCase {
    func testMissingComponentReturnsNil() {
        XCTAssertNil(
            NIIslandFactoryRegistry<String>().entry(for: "missing")
        )
    }

    func testRegistrationKeepsAccessibilityAndFactoryTogether() {
        let registry = NIIslandFactoryRegistry<String>()
        registry.register(
            type: "engine",
            accessibility: .native,
            factory: "factory-a"
        )

        let entry = registry.entry(for: "engine")
        XCTAssertEqual(entry?.accessibility, .native)
        XCTAssertEqual(entry?.factory, "factory-a")
    }

    func testEquivalentRegistrationKeepsFirstFactory() {
        let registry = NIIslandFactoryRegistry<String>()
        registry.register(
            type: "engine",
            accessibility: .web,
            factory: "first"
        )
        registry.register(
            type: "engine",
            accessibility: .web,
            factory: "second"
        )

        XCTAssertEqual(registry.entry(for: "engine")?.factory, "first")
    }
}
