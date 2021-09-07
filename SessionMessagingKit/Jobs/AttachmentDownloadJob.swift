import Foundation
import SessionUtilitiesKit
import SessionSnodeKit
import SignalCoreKit

public final class AttachmentDownloadJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public let attachmentID: String
    public let tsMessageID: String
    public let threadID: String
    public var delegate: JobDelegate?
    public var id: String?
    public var failureCount: UInt = 0
    public var isDeferred = false

    public enum Error : LocalizedError {
        case noAttachment
        case invalidURL

        public var errorDescription: String? {
            switch self {
            case .noAttachment: return "No such attachment."
            case .invalidURL: return "Invalid file URL."
            }
        }
    }

    // MARK: Settings
    public class var collection: String { return "AttachmentDownloadJobCollection" }
    public static let maxFailureCount: UInt = 20

    // MARK: Initialization
    public init(attachmentID: String, tsMessageID: String, threadID: String) {
        self.attachmentID = attachmentID
        self.tsMessageID = tsMessageID
        self.threadID = threadID
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
            let tsMessageID = coder.decodeObject(forKey: "tsIncomingMessageID") as! String?,
            let threadID = coder.decodeObject(forKey: "threadID") as! String?,
            let id = coder.decodeObject(forKey: "id") as! String? else { return nil }
        self.attachmentID = attachmentID
        self.tsMessageID = tsMessageID
        self.threadID = threadID
        self.id = id
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
        self.isDeferred = coder.decodeBool(forKey: "isDeferred")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(attachmentID, forKey: "attachmentID")
        coder.encode(tsMessageID, forKey: "tsIncomingMessageID")
        coder.encode(threadID, forKey: "threadID")
        coder.encode(id, forKey: "id")
        coder.encode(failureCount, forKey: "failureCount")
        coder.encode(isDeferred, forKey: "isDeferred")
    }

    // MARK: Running
    public func execute() {
        if let id = id {
            JobQueue.currentlyExecutingJobs.insert(id)
        }
        guard !isDeferred else { return }
        if TSAttachment.fetch(uniqueId: attachmentID) is TSAttachmentStream {
            // FIXME: It's not clear * how * this happens, but apparently we can get to this point
            // from time to time with an already downloaded attachment.
            return handleSuccess()
        }
        guard let pointer = TSAttachment.fetch(uniqueId: attachmentID) as? TSAttachmentPointer else {
            return handleFailure(error: Error.noAttachment)
        }
        let storage = SNMessagingKitConfiguration.shared.storage
        storage.write(with: { transaction in
            storage.setAttachmentState(to: .downloading, for: pointer, associatedWith: self.tsMessageID, using: transaction)
        }, completion: { })
        let temporaryFilePath = URL(fileURLWithPath: OWSTemporaryDirectoryAccessibleAfterFirstAuth() + UUID().uuidString)
        let handleFailure: (Swift.Error) -> Void = { error in // Intentionally capture self
            OWSFileSystem.deleteFile(temporaryFilePath.absoluteString)
            if let error = error as? Error, case .noAttachment = error {
                storage.write(with: { transaction in
                    storage.setAttachmentState(to: .failed, for: pointer, associatedWith: self.tsMessageID, using: transaction)
                }, completion: { })
                self.handlePermanentFailure(error: error)
            } else if let error = error as? OnionRequestAPI.Error, case .httpRequestFailedAtDestination(let statusCode, _, _) = error,
                statusCode == 400 {
                // Otherwise, the attachment will show a state of downloading forever,
                // and the message won't be able to be marked as read.
                storage.write(with: { transaction in
                    storage.setAttachmentState(to: .failed, for: pointer, associatedWith: self.tsMessageID, using: transaction)
                }, completion: { })
                // This usually indicates a file that has expired on the server, so there's no need to retry.
                self.handlePermanentFailure(error: error)
            } else {
                self.handleFailure(error: error)
            }
        }
        if let tsMessage = TSMessage.fetch(uniqueId: tsMessageID), let v2OpenGroup = storage.getV2OpenGroup(for: tsMessage.uniqueThreadId) {
            guard let fileAsString = pointer.downloadURL.split(separator: "/").last, let file = UInt64(fileAsString) else {
                return handleFailure(Error.invalidURL)
            }
            OpenGroupAPIV2.download(file, from: v2OpenGroup.room, on: v2OpenGroup.server).done(on: DispatchQueue.global(qos: .userInitiated)) { data in
                self.handleDownloadedAttachment(data: data, temporaryFilePath: temporaryFilePath, pointer: pointer, failureHandler: handleFailure)
            }.catch(on: DispatchQueue.global()) { error in
                handleFailure(error)
            }
        } else {
            guard let fileAsString = pointer.downloadURL.split(separator: "/").last, let file = UInt64(fileAsString) else {
                return handleFailure(Error.invalidURL)
            }
            let useOldServer = pointer.downloadURL.contains(FileServerAPIV2.oldServer)
            FileServerAPIV2.download(file, useOldServer: useOldServer).done(on: DispatchQueue.global(qos: .userInitiated)) { data in
                self.handleDownloadedAttachment(data: data, temporaryFilePath: temporaryFilePath, pointer: pointer, failureHandler: handleFailure)
            }.catch(on: DispatchQueue.global()) { error in
                handleFailure(error)
            }
        }
    }
    
    private func handleDownloadedAttachment(data: Data, temporaryFilePath: URL, pointer: TSAttachmentPointer, failureHandler: (Swift.Error) -> Void) {
        let storage = SNMessagingKitConfiguration.shared.storage
        do {
            try data.write(to: temporaryFilePath, options: .atomic)
        } catch {
            return failureHandler(error)
        }
        let plaintext: Data
        if let key = pointer.encryptionKey, let digest = pointer.digest, key.count > 0 && digest.count > 0 {
            do {
                plaintext = try Cryptography.decryptAttachment(data, withKey: key, digest: digest, unpaddedSize: pointer.byteCount)
            } catch {
                return failureHandler(error)
            }
        } else {
            plaintext = data // Open group attachments are unencrypted
        }
        let stream = TSAttachmentStream(pointer: pointer)
        do {
            try stream.write(plaintext)
        } catch {
            return failureHandler(error)
        }
        OWSFileSystem.deleteFile(temporaryFilePath.absoluteString)
        storage.write(with: { transaction in
            storage.persist(stream, associatedWith: self.tsMessageID, using: transaction)
        }, completion: {
            self.handleSuccess()
        })
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }
    
    private func handlePermanentFailure(error: Swift.Error) {
        delegate?.handleJobFailedPermanently(self, with: error)
    }

    private func handleFailure(error: Swift.Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}
