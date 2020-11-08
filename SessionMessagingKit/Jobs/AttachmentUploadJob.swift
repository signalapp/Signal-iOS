import SessionUtilities

// TODO: Implementation

public final class AttachmentUploadJob : NSObject, Job,  NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility

    // MARK: Settings
    private static let maxRetryCount: UInt = 20

    // MARK: Coding
    public init?(coder: NSCoder) { }

    public func encode(with coder: NSCoder) { }

    // MARK: Running
    public func execute() { }

    private func handleSuccess() { }

    private func handleFailure(error: Error) { }
}

