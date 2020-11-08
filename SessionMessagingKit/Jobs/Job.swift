
public protocol Job : class {
    var delegate: JobDelegate? { get set }
    var failureCount: UInt { get set }

    static var maxFailureCount: UInt { get }

    func execute()
}
