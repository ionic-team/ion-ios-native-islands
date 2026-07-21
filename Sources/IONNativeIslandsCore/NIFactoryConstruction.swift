import Foundation

/// Pure boundary around app-owned factory execution. Construction errors become data so the
/// plugin can degrade only the affected island instead of escaping the ledger pass.
enum NIFactoryConstruction<Value> {
    case created(Value)
    case missing
    case failed(errorType: String)

    static func run(_ factory: (() throws -> Value)?) -> NIFactoryConstruction<Value> {
        guard let factory else { return .missing }
        do {
            return try .created(factory())
        } catch {
            return .failed(errorType: String(describing: type(of: error)))
        }
    }
}
