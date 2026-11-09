import XCTest
@testable import IONNativeIslandsLib

final class NIIslandFactoryRegistryTests: XCTestCase {
    func testRegisteringANameAgainKeepsTheFirstFactory() {
        let registry = NIIslandFactoryRegistry<String>()
        registry.register(type: "engine", accessibility: .native, factory: "first")
        registry.register(type: "engine", accessibility: .native, factory: "second")
        XCTAssertEqual(registry.entry(for: "engine")?.factory, "first")
        XCTAssertEqual(registry.entry(for: "engine")?.accessibility, .native)
        XCTAssertNil(registry.entry(for: "missing"))
    }
}
