import Foundation
import SessionUtilitiesKit
import SignalCoreKit

public final class AttachmentDownloadJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let attachmentID: String
    public var id: String?
    public var failureCount: UInt = 0

    public enum Error : LocalizedError {
        case noAttachment

        public var errorDescription: String? {
            switch self {
            case .noAttachment: return "No such attachment."
            }
        }
    }

    // MARK: Settings
    public class var collection: String { return "AttachmentDownloadJobCollection" }
    public static let maxFailureCount: UInt = 20

    // MARK: Initialization
    public init(attachmentID: String) {
        self.attachmentID = attachmentID
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String? else { return nil }
        self.attachmentID = attachmentID
    }

    public func encode(with coder: NSCoder) {
        coder.encode(attachmentID, forKey: "attachmentID")
    }

    // MARK: Running
    public func execute() {
        guard let pointer = TSAttachmentPointer.fetch(uniqueId: attachmentID) else {
            return handleFailure(error: Error.noAttachment)
        }
        let temporaryFilePath = URL(fileURLWithPath: OWSTemporaryDirectoryAccessibleAfterFirstAuth() + UUID().uuidString)
        FileServerAPI.downloadAttachment(from: pointer.downloadURL).done(on: DispatchQueue.global(qos: .userInitiated)) { data in // Intentionally capture self
            do {
                try data.write(to: temporaryFilePath, options: .atomic)
            } catch {
                return self.handleFailure(error: error)
            }
            let plaintext: Data
            if let key = pointer.encryptionKey, let digest = pointer.digest {
                do {
                    plaintext = try Cryptography.decryptAttachment(data, withKey: key, digest: digest, unpaddedSize: pointer.byteCount)
                } catch {
                    return self.handleFailure(error: error)
                }
            } else {
                plaintext = data // Open group attachments are unencrypted
            }
            let stream = TSAttachmentStream(pointer: pointer)
            do {
                try stream.write(plaintext)
            } catch {
                return self.handleFailure(error: error)
            }
            OWSFileSystem.deleteFile(temporaryFilePath.absoluteString)
            Configuration.shared.storage.withAsync({ transaction in
                stream.save(with: transaction as! YapDatabaseReadWriteTransaction)
                // TODO: Update the message
            }, completion: { })
        }.catch(on: DispatchQueue.global()) { error in
            self.handleFailure(error: error)
        }
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Swift.Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

