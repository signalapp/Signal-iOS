import SessionUtilitiesKit

// TODO: Implementation

public final class AttachmentUploadJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    public var id: String?
    public var failureCount: UInt = 0

    // MARK: Settings
    public class var collection: String { return "AttachmentUploadJobCollection" }
    public static let maxFailureCount: UInt = 20

    // MARK: Coding
    public init?(coder: NSCoder) { }

    public func encode(with coder: NSCoder) { }

    // MARK: Running
    public func execute() { }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

