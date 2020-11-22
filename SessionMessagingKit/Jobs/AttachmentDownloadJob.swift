import Foundation
import SessionUtilitiesKit
import SignalCoreKit

public final class AttachmentDownloadJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let attachmentID: String
    private let tsIncomingMessageID: String
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
    public init(attachmentID: String, tsIncomingMessageID: String) {
        self.attachmentID = attachmentID
        self.tsIncomingMessageID = tsIncomingMessageID
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
            let tsIncomingMessageID = coder.decodeObject(forKey: "tsIncomingMessageID") as! String? else { return nil }
        self.attachmentID = attachmentID
        self.tsIncomingMessageID = tsIncomingMessageID
    }

    public func encode(with coder: NSCoder) {
        coder.encode(attachmentID, forKey: "attachmentID")
        coder.encode(tsIncomingMessageID, forKey: "tsIncomingMessageID")
    }

    // MARK: Running
    public func execute() {
        guard let pointer = TSAttachmentPointer.fetch(uniqueId: attachmentID) else {
            return handleFailure(error: Error.noAttachment)
        }
        let storage = Configuration.shared.storage
        storage.withAsync({ transaction in
            storage.setAttachmentState(to: .downloading, for: pointer, associatedWith: self.tsIncomingMessageID, using: transaction)
        }, completion: { })
        let temporaryFilePath = URL(fileURLWithPath: OWSTemporaryDirectoryAccessibleAfterFirstAuth() + UUID().uuidString)
        let handleFailure: (Swift.Error) -> Void = { error in // Intentionally capture self
            OWSFileSystem.deleteFile(temporaryFilePath.absoluteString)
            storage.withAsync({ transaction in
                storage.setAttachmentState(to: .failed, for: pointer, associatedWith: self.tsIncomingMessageID, using: transaction)
            }, completion: { })
            self.handleFailure(error: error)
        }
        FileServerAPI.downloadAttachment(from: pointer.downloadURL).done(on: DispatchQueue.global(qos: .userInitiated)) { data in
            do {
                try data.write(to: temporaryFilePath, options: .atomic)
            } catch {
                return handleFailure(error)
            }
            let plaintext: Data
            if let key = pointer.encryptionKey, let digest = pointer.digest {
                do {
                    plaintext = try Cryptography.decryptAttachment(data, withKey: key, digest: digest, unpaddedSize: pointer.byteCount)
                } catch {
                    return handleFailure(error)
                }
            } else {
                plaintext = data // Open group attachments are unencrypted
            }
            let stream = TSAttachmentStream(pointer: pointer)
            do {
                try stream.write(plaintext)
            } catch {
                return handleFailure(error)
            }
            OWSFileSystem.deleteFile(temporaryFilePath.absoluteString)
            storage.withAsync({ transaction in
                storage.persist(stream, associatedWith: self.tsIncomingMessageID, using: transaction)
            }, completion: { })
        }.catch(on: DispatchQueue.global()) { error in
            handleFailure(error)
        }
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Swift.Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

