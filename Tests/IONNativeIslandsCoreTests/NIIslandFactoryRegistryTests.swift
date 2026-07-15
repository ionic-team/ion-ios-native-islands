import XCTest
@testable import IONNativeIslandsCore

final class NIIslandFactoryRegistryTests: XCTestCase {
    func testMissingTypeReturnsNil() {
        XCTAssertNil(NIIslandFactoryRegistry<String>().entry(for: "missing"))
    }

    func testEntryKeepsFactoryAndPolicyTogether() {
        let registry = NIIslandFactoryRegistry<String>()
        registry.register(
            type: "engine", allowedCommands: ["create", "start"],
            capability: "custom.engine", accessibilityOwner: "native", factory: "factory-a"
        )

        let entry = registry.entry(for: "engine")
        XCTAssertEqual(entry?.allowedCommands, ["create", "start"])
        XCTAssertEqual(entry?.capability, "custom.engine")
        XCTAssertEqual(entry?.accessibilityOwner, "native")
        XCTAssertEqual(entry?.factory, "factory-a")
    }

    func testReRegistrationAtomicallyReplacesTheWholeEntry() {
        let registry = NIIslandFactoryRegistry<String>()
        registry.register(
            type: "engine", allowedCommands: ["old"],
            capability: "old.capability", accessibilityOwner: "web", factory: "old-factory"
        )
        registry.register(
            type: "engine", allowedCommands: ["new"],
            capability: "new.capability", accessibilityOwner: "native", factory: "new-factory"
        )

        let entry = registry.entry(for: "engine")
        XCTAssertEqual(entry?.allowedCommands, ["new"])
        XCTAssertEqual(entry?.capability, "new.capability")
        XCTAssertEqual(entry?.accessibilityOwner, "native")
        XCTAssertEqual(entry?.factory, "new-factory")
    }

    func testRegistrationSurvivesIndependentConsumerLifetimes() {
        let registry = NIIslandFactoryRegistry<String>()
        registry.register(
            type: "engine", allowedCommands: ["create"],
            capability: "custom.engine", factory: "process-factory"
        )

        for _ in 0..<3 {
            XCTAssertEqual(registry.entry(for: "engine")?.factory, "process-factory")
        }
    }
}
