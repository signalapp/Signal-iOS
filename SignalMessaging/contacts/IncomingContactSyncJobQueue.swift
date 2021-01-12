//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension Notification.Name {
    static let IncomingContactSyncDidComplete = Notification.Name("IncomingContactSyncDidComplete")
}

@objc(OWSIncomingContactSyncJobQueue)
public class IncomingContactSyncJobQueue: NSObject, JobQueue {

    public typealias DurableOperationType = IncomingContactSyncOperation
    public let requiresInternet: Bool = true
    public static let maxRetries: UInt = 4
    @objc
    public static let jobRecordLabel: String = OWSIncomingContactSyncJobRecord.defaultLabel
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    public var runningOperations = AtomicArray<IncomingContactSyncOperation>()
    public var isSetup = AtomicBool(false)

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public func didMarkAsReady(oldJobRecord: OWSIncomingContactSyncJobRecord, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "IncomingContactSyncJobQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSIncomingContactSyncJobRecord) -> OperationQueue {
        return defaultQueue
    }

    public func buildOperation(jobRecord: OWSIncomingContactSyncJobRecord, transaction: SDSAnyReadTransaction) throws -> IncomingContactSyncOperation {
        return IncomingContactSyncOperation(jobRecord: jobRecord)
    }

    @objc
    public func add(attachmentId: String, transaction: SDSAnyWriteTransaction) {
        let jobRecord = OWSIncomingContactSyncJobRecord(attachmentId: attachmentId,
                                                        label: self.jobRecordLabel)
        self.add(jobRecord: jobRecord, transaction: transaction)
    }
}

public class IncomingContactSyncOperation: OWSOperation, DurableOperation {
    public typealias JobRecordType = OWSIncomingContactSyncJobRecord
    public typealias DurableOperationDelegateType = IncomingContactSyncJobQueue
    public weak var durableOperationDelegate: IncomingContactSyncJobQueue?
    public var jobRecord: OWSIncomingContactSyncJobRecord
    public var operation: OWSOperation {
        return self
    }

    public var newThreads: [(threadId: String, sortOrder: UInt32)] = []

    // MARK: -

    init(jobRecord: OWSIncomingContactSyncJobRecord) {
        self.jobRecord = jobRecord
    }

    // MARK: - Dependencies

    var attachmentDownloads: OWSAttachmentDownloads {
        return SSKEnvironment.shared.attachmentDownloads
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: - Durable Operation Overrides

    enum IncomingContactSyncError: Error {
        case malformed(_ description: String)
    }

    public override func run() {
        firstly { () -> Promise<TSAttachmentStream> in
            try self.getAttachmentStream()
        }.done(on: .global()) { attachmentStream in
            self.newThreads = []
            try Bench(title: "processing incoming contact sync file") {
                try self.process(attachmentStream: attachmentStream)
            }
            self.databaseStorage.write { transaction in
                guard let attachmentStream = TSAttachmentStream.anyFetch(uniqueId: self.jobRecord.attachmentId, transaction: transaction) else {
                    owsFailDebug("attachmentStream was unexpectedly nil")
                    return
                }
                attachmentStream.anyRemove(transaction: transaction)
            }
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
        // add user info for thread ordering
        NotificationCenter.default.post(name: .IncomingContactSyncDidComplete, object: self)
    }

    public override func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    public override func didFail(error: Error) {
        Logger.error("failed with error: \(error)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }

    // MARK: - Private

    private func getAttachmentStream() throws -> Promise<TSAttachmentStream> {
        Logger.debug("attachmentId: \(jobRecord.attachmentId)")

        guard let attachment = (databaseStorage.read { transaction in
            return TSAttachment.anyFetch(uniqueId: self.jobRecord.attachmentId, transaction: transaction)
        }) else {
            throw OWSAssertionError("missing attachment")
        }

        switch attachment {
        case let attachmentPointer as TSAttachmentPointer:
            return self.attachmentDownloads.downloadPromise(attachmentPointer: attachmentPointer,
                                                            category: .other,
                                                            downloadBehavior: .bypassAll)
        case let attachmentStream as TSAttachmentStream:
            return Promise.value(attachmentStream)
        default:
            throw OWSAssertionError("unexpected attachment type: \(attachment)")
        }
    }

    private func buildContact(_ contactDetails: ContactDetails, transaction: SDSAnyWriteTransaction) throws -> Contact {

        var userTextPhoneNumbers: [String] = []
        var phoneNumberNameMap: [String: String] = [:]
        var parsedPhoneNumbers: [PhoneNumber] = []
        if let phoneNumber = contactDetails.address.phoneNumber,
            let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumber) {
            userTextPhoneNumbers.append(phoneNumber)
            parsedPhoneNumbers.append(parsedPhoneNumber)
            phoneNumberNameMap[parsedPhoneNumber.toE164()] = CommonStrings.mainPhoneNumberLabel
        }

        let fullName: String
        if let name: String = contactDetails.name {
            fullName = name
        } else {
            fullName = self.contactsManager.displayName(for: contactDetails.address, transaction: transaction)
        }

        guard let serviceIdentifier = contactDetails.address.serviceIdentifier else {
            throw IncomingContactSyncError.malformed("serviceIdentifier was unexpectedly nil")
        }

        return Contact(uniqueId: serviceIdentifier,
                       cnContactId: nil,
                       firstName: nil,
                       lastName: nil,
                       nickname: nil,
                       fullName: fullName,
                       userTextPhoneNumbers: userTextPhoneNumbers,
                       phoneNumberNameMap: phoneNumberNameMap,
                       parsedPhoneNumbers: parsedPhoneNumbers,
                       emails: [],
                       imageDataToHash: contactDetails.avatarData)
    }

    private func process(attachmentStream: TSAttachmentStream) throws {
        guard let fileUrl = attachmentStream.originalMediaURL else {
            throw OWSAssertionError("fileUrl was unexpectedly nil")
        }
        try Data(contentsOf: fileUrl, options: .mappedIfSafe).withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let contactStream = ContactsInputStream(inputStream: inputStream)

                try databaseStorage.write { transaction in
                    while let nextContact = try contactStream.decodeContact() {
                        try autoreleasepool {
                            try self.process(contactDetails: nextContact, transaction: transaction)
                        }
                    }

                    // Always fire just one identity change notification, rather than potentially
                    // once per contact. It's possible that *no* identities actually changed,
                    // but we have no convenient way to track that.
                    self.identityManager.fireIdentityStateChangeNotification(after: transaction)
                }
            }
        }
    }

    private func process(contactDetails: ContactDetails, transaction: SDSAnyWriteTransaction) throws {
        Logger.debug("contactDetails: \(contactDetails)")

        // Mark as registered, since we trust the contact information sent from our other devices.
        SignalRecipient.mark(asRegisteredAndGet: contactDetails.address, trustLevel: .high, transaction: transaction)

        let contactAvatarHash: Data?
        let contactAvatarJpegData: Data?
        if let avatarData = contactDetails.avatarData {
            contactAvatarHash = Cryptography.computeSHA256Digest(avatarData)
            contactAvatarJpegData = UIImage.validJpegData(fromAvatarData: avatarData)
        } else {
            contactAvatarHash = nil
            contactAvatarJpegData = nil
        }

        if let existingAccount = self.contactsManager.fetchSignalAccount(for: contactDetails.address, transaction: transaction) {
            if existingAccount.contact == nil {
                owsFailDebug("Persisted account missing contact.")
            }
            if let contact = existingAccount.contact,
                contact.isFromContactSync {
                let contact = try self.buildContact(contactDetails, transaction: transaction)
                existingAccount.updateWithContact(contact, transaction: transaction)
            }
        } else {
            let contact = try self.buildContact(contactDetails, transaction: transaction)
            let newAccount = SignalAccount(contact: contact,
                                           contactAvatarHash: contactAvatarHash,
                                           contactAvatarJpegData: contactAvatarJpegData,
                                           multipleAccountLabelText: "",
                                           recipientPhoneNumber: contactDetails.address.phoneNumber,
                                           recipientUUID: contactDetails.address.uuidString)
            newAccount.anyInsert(transaction: transaction)
        }

        let contactThread: TSContactThread
        let isNewThread: Bool
        var threadDidChange = false
        if let existingThread = TSContactThread.getWithContactAddress(contactDetails.address, transaction: transaction) {
            contactThread = existingThread
            isNewThread = false
        } else {
            let newThread = TSContactThread(contactAddress: contactDetails.address)
            newThread.shouldThreadBeVisible = true

            contactThread = newThread
            isNewThread = true
        }

        if let conversationColorNameValue = contactDetails.conversationColorName {
            let conversationColorName = ConversationColorName(rawValue: conversationColorNameValue)
            if contactThread.conversationColorName != conversationColorName {
                threadDidChange = true
                contactThread.conversationColorName = conversationColorName
            }
        }

        if isNewThread {
            contactThread.anyInsert(transaction: transaction)
            let inboxSortOrder = contactDetails.inboxSortOrder ?? UInt32.max
            newThreads.append((threadId: contactThread.uniqueId, sortOrder: inboxSortOrder))
            if let isArchived = contactDetails.isArchived, isArchived == true {
                contactThread.archiveThread(updateStorageService: false, transaction: transaction)
            }
        } else if threadDidChange {
            contactThread.anyOverwritingUpdate(transaction: transaction)
        }

        let disappearingMessageToken = DisappearingMessageToken.token(forProtoExpireTimer: contactDetails.expireTimer)
        GroupManager.remoteUpdateDisappearingMessages(withContactOrV1GroupThread: contactThread,
                                                      disappearingMessageToken: disappearingMessageToken,
                                                      groupUpdateSourceAddress: nil,
                                                      transaction: transaction)

        if let verifiedProto = contactDetails.verifiedProto {
            try self.identityManager.processIncomingVerifiedProto(verifiedProto,
                                                                  transaction: transaction)
        }

        if let profileKey = contactDetails.profileKey {
            self.profileManager.setProfileKeyData(profileKey,
                                                  for: contactDetails.address,
                                                  wasLocallyInitiated: false,
                                                  transaction: transaction)
        }

        if contactDetails.isBlocked {
            if !self.blockingManager.isAddressBlocked(contactDetails.address) {
                self.blockingManager.addBlockedAddress(contactDetails.address,
                                                       blockMode: .remote,
                                                       transaction: transaction)
            }
        } else {
            if self.blockingManager.isAddressBlocked(contactDetails.address) {
                self.blockingManager.removeBlockedAddress(contactDetails.address,
                                                          wasLocallyInitiated: false,
                                                          transaction: transaction)
            }
        }
    }
}
