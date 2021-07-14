import SessionUtilitiesKit
import SessionSnodeKit

@objc(SNMessageSendJob)
public final class MessageSendJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public let message: Message
    public let destination: Message.Destination
    public var delegate: JobDelegate?
    public var id: String?
    public var failureCount: UInt = 0

    // MARK: Settings
    public class var collection: String { return "MessageSendJobCollection" }
    public static let maxFailureCount: UInt = 10

    // MARK: Initialization
    @objc public convenience init(message: Message, publicKey: String) { self.init(message: message, destination: .contact(publicKey: publicKey)) }
    @objc public convenience init(message: Message, groupPublicKey: String) { self.init(message: message, destination: .closedGroup(groupPublicKey: groupPublicKey)) }

    public init(message: Message, destination: Message.Destination) {
        self.message = message
        self.destination = destination
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let message = coder.decodeObject(forKey: "message") as! Message?,
            var rawDestination = coder.decodeObject(forKey: "destination") as! String?,
            let id = coder.decodeObject(forKey: "id") as! String? else { return nil }
        self.message = message
        if rawDestination.removePrefix("contact(") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let publicKey = rawDestination
            destination = .contact(publicKey: publicKey)
        } else if rawDestination.removePrefix("closedGroup(") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let groupPublicKey = rawDestination
            destination = .closedGroup(groupPublicKey: groupPublicKey)
        } else if rawDestination.removePrefix("openGroup(") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let components = rawDestination.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard components.count == 2, let channel = UInt64(components[0]) else { return nil }
            let server = components[1]
            destination = .openGroup(channel: channel, server: server)
        } else if rawDestination.removePrefix("openGroupV2(") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let components = rawDestination.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard components.count == 2 else { return nil }
            let room = components[0]
            let server = components[1]
            destination = .openGroupV2(room: room, server: server)
        } else {
            return nil
        }
        self.id = id
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(message, forKey: "message")
        switch destination {
        case .contact(let publicKey): coder.encode("contact(\(publicKey))", forKey: "destination")
        case .closedGroup(let groupPublicKey): coder.encode("closedGroup(\(groupPublicKey))", forKey: "destination")
        case .openGroup(let channel, let server): coder.encode("openGroup(\(channel), \(server))", forKey: "destination")
        case .openGroupV2(let room, let server): coder.encode("openGroupV2(\(room), \(server))", forKey: "destination")
        }
        coder.encode(id, forKey: "id")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        if let id = id {
            JobQueue.currentlyExecutingJobs.insert(id)
        }
        let storage = SNMessagingKitConfiguration.shared.storage
        if let message = message as? VisibleMessage {
            guard TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) != nil else { return } // The message has been deleted
            let attachments = message.attachmentIDs.compactMap { TSAttachment.fetch(uniqueId: $0) as? TSAttachmentStream }
            let attachmentsToUpload = attachments.filter { !$0.isUploaded }
            attachmentsToUpload.forEach { attachment in
                if storage.getAttachmentUploadJob(for: attachment.uniqueId!) != nil {
                    // Wait for it to finish
                } else {
                    let job = AttachmentUploadJob(attachmentID: attachment.uniqueId!, threadID: message.threadID!, message: message, messageSendJobID: id!)
                    storage.write(with: { transaction in
                        JobQueue.shared.add(job, using: transaction)
                    }, completion: { })
                }
            }
            if !attachmentsToUpload.isEmpty { return } // Wait for all attachments to upload before continuing
        }
        storage.write(with: { transaction in // Intentionally capture self
            MessageSender.send(self.message, to: self.destination, using: transaction).done(on: DispatchQueue.global(qos: .userInitiated)) {
                self.handleSuccess()
            }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                SNLog("Couldn't send message due to error: \(error).")
                if let error = error as? MessageSender.Error, !error.isRetryable {
                    self.handlePermanentFailure(error: error)
                } else if let error = error as? OnionRequestAPI.Error, case .httpRequestFailedAtDestination(let statusCode, _, _) = error,
                    statusCode == 429 { // Rate limited
                    self.handlePermanentFailure(error: error)
               } else {
                    self.handleFailure(error: error)
                }
            }
        }, completion: { })
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }
    
    private func handlePermanentFailure(error: Error) {
        delegate?.handleJobFailedPermanently(self, with: error)
    }

    private func handleFailure(error: Error) {
        SNLog("Failed to send \(type(of: message)).")
        if let message = message as? VisibleMessage {
            guard TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) != nil else { return } // The message has been deleted
        }
        delegate?.handleJobFailed(self, with: error)
    }
}

// MARK: Convenience
private extension String {

    @discardableResult
    mutating func removePrefix<T : StringProtocol>(_ prefix: T) -> Bool {
        guard hasPrefix(prefix) else { return false }
        removeFirst(prefix.count)
        return true
    }

    @discardableResult
    mutating func removeSuffix<T : StringProtocol>(_ suffix: T) -> Bool {
        guard hasSuffix(suffix) else { return false }
        removeLast(suffix.count)
        return true
    }
}

