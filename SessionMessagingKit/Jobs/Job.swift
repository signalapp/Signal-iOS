
@objc(SNJob)
public protocol Job : NSCoding {
    var delegate: JobDelegate? { get set }
    var id: String? { get set }
    var failureCount: UInt { get set }

    static var collection: String { get }
    static var maxFailureCount: UInt { get }

    func execute()
}
