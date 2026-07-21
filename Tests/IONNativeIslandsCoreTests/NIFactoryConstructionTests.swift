import XCTest
@testable import IONNativeIslandsLib

final class NIFactoryConstructionTests: XCTestCase {
    private enum FixtureError: Error { case construction }

    func testCreatesExactlyOnce() {
        let expected = NSObject()
        var calls = 0
        let result = NIFactoryConstruction<NSObject>.run {
            calls += 1
            return expected
        }

        XCTAssertEqual(calls, 1)
        guard case let .created(value) = result else {
            return XCTFail("expected created result")
        }
        XCTAssertTrue(value === expected)
    }

    func testDistinguishesMissingFactory() {
        let result = NIFactoryConstruction<NSObject>.run(nil)
        guard case .missing = result else { return XCTFail("expected missing result") }
    }

    func testConvertsThrownFactoryIntoStableFailureType() {
        let result = NIFactoryConstruction<NSObject>.run { throw FixtureError.construction }
        guard case let .failed(errorType) = result else {
            return XCTFail("expected failed result")
        }
        XCTAssertEqual(errorType, "FixtureError")
    }
}
