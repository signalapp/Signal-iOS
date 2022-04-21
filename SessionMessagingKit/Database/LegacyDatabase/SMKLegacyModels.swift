// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Mantle
import YapDatabase
import SignalCoreKit

public enum Legacy {
    // MARK: - Collections and Keys
    
    internal static let contactThreadPrefix = "c"
    internal static let groupThreadPrefix = "g"
    internal static let closedGroupIdPrefix = "__textsecure_group__!"
    internal static let closedGroupKeyPairPrefix = "SNClosedGroupEncryptionKeyPairCollection-"
    
    public static let contactCollection = "LokiContactCollection"
    internal static let threadCollection = "TSThread"
    internal static let disappearingMessagesCollection = "OWSDisappearingMessagesConfiguration"
    
    internal static let closedGroupPublicKeyCollection = "SNClosedGroupPublicKeyCollection"
    internal static let closedGroupFormationTimestampCollection = "SNClosedGroupFormationTimestampCollection"
    internal static let closedGroupZombieMembersCollection = "SNClosedGroupZombieMembersCollection"
    
    internal static let openGroupCollection = "SNOpenGroupCollection"
    internal static let openGroupUserCountCollection = "SNOpenGroupUserCountCollection"
    internal static let openGroupImageCollection = "SNOpenGroupImageCollection"
    internal static let openGroupLastMessageServerIDCollection = "SNLastMessageServerIDCollection"
    internal static let openGroupLastDeletionServerIDCollection = "SNLastDeletionServerIDCollection"
    internal static let openGroupServerIdToUniqueIdLookupCollection = "SNOpenGroupServerIdToUniqueIdLookup"
    
    internal static let interactionCollection = "TSInteraction"
    internal static let attachmentsCollection = "TSAttachements"
    internal static let outgoingReadReceiptManagerCollection = "kOutgoingReadReceiptManagerCollection"
    
    internal static let notifyPushServerJobCollection = "NotifyPNServerJobCollection"
    internal static let messageReceiveJobCollection = "MessageReceiveJobCollection"
    internal static let messageSendJobCollection = "MessageSendJobCollection"
    internal static let attachmentUploadJobCollection = "AttachmentUploadJobCollection"
    internal static let attachmentDownloadJobCollection = "AttachmentDownloadJobCollection"
    
    internal static let preferencesCollection = "SignalPreferences"
    internal static let preferencesKeyNotificationPreviewType = "preferencesKeyNotificationPreviewType"
    internal static let preferencesKeyScreenSecurityDisabled = "Screen Security Key"
    internal static let preferencesKeyLastRecordedPushToken = "LastRecordedPushToken"
    internal static let preferencesKeyLastRecordedVoipToken = "LastRecordedVoipToken"
    
    internal static let readReceiptManagerCollection = "OWSReadReceiptManagerCollection"
    internal static let readReceiptManagerAreReadReceiptsEnabled = "areReadReceiptsEnabled"
    
    internal static let typingIndicatorsCollection = "TypingIndicators"
    internal static let typingIndicatorsEnabledKey = "kDatabaseKey_TypingIndicatorsEnabled"
    
    internal static let soundsStorageNotificationCollection = "kOWSSoundsStorageNotificationCollection"
    internal static let soundsGlobalNotificationKey = "kOWSSoundsStorageGlobalNotificationKey"
    
    internal static let userDefaultsHasHiddenMessageRequests = "hasHiddenMessageRequests"
    
    // MARK: - Types
    
    public typealias Contact = _LegacyContact
    public typealias DisappearingMessagesConfiguration = _LegacyDisappearingMessagesConfiguration
    
    @objc(SNProfile)
    public class Profile: NSObject, NSCoding {
        public var displayName: String?
        public var profileKey: Data?
        public var profilePictureURL: String?

    @objc(NotifyPNServerJob)
    internal final class NotifyPNServerJob: NSObject, NSCoding {
        @objc(SnodeMessage)
        internal final class SnodeMessage: NSObject, NSCoding {
            public let recipient: String
            public let data: LosslessStringConvertible
            public let ttl: UInt64
            public let timestamp: UInt64    // Milliseconds

            // MARK: - Coding
            
            public init?(coder: NSCoder) {
                guard
                    let recipient = coder.decodeObject(forKey: "recipient") as! String?,
                    let data = coder.decodeObject(forKey: "data") as! String?,
                    let ttl = coder.decodeObject(forKey: "ttl") as! UInt64?,
                    let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64?
                else { return nil }
                
                self.recipient = recipient
                self.data = data
                self.ttl = ttl
                self.timestamp = timestamp
                
                super.init()
            }

            public func encode(with coder: NSCoder) {
                coder.encode(recipient, forKey: "recipient")
                coder.encode(data, forKey: "data")
                coder.encode(ttl, forKey: "ttl")
                coder.encode(timestamp, forKey: "timestamp")
            }
        }
        
        public let message: SnodeMessage
        public var id: String?
        public var failureCount: UInt = 0

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard
                let message = coder.decodeObject(forKey: "message") as! SnodeMessage?,
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
            self.message = message
            self.id = id
            self.failureCount = ((coder.decodeObject(forKey: "failureCount") as? UInt) ?? 0)
        }

        public func encode(with coder: NSCoder) {
            coder.encode(message, forKey: "message")
            coder.encode(id, forKey: "id")
            coder.encode(failureCount, forKey: "failureCount")
        }
    }

    @objc(MessageReceiveJob)
    public final class MessageReceiveJob: NSObject, NSCoding {
        public let data: Data
        public let serverHash: String?
        public let openGroupMessageServerID: UInt64?
        public let openGroupID: String?
        public let isBackgroundPoll: Bool
        public var id: String?
        public var failureCount: UInt = 0

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard
                let data = coder.decodeObject(forKey: "data") as! Data?,
                let id = coder.decodeObject(forKey: "id") as! String?,
                let isBackgroundPoll = coder.decodeObject(forKey: "isBackgroundPoll") as! Bool?
            else { return nil }
            
            self.data = data
            self.serverHash = coder.decodeObject(forKey: "serverHash") as! String?
            self.openGroupMessageServerID = coder.decodeObject(forKey: "openGroupMessageServerID") as! UInt64?
            self.openGroupID = coder.decodeObject(forKey: "openGroupID") as! String?
            self.isBackgroundPoll = isBackgroundPoll
            self.id = id
            self.failureCount = ((coder.decodeObject(forKey: "failureCount") as? UInt) ?? 0)
        }

        public func encode(with coder: NSCoder) {
            coder.encode(data, forKey: "data")
            coder.encode(serverHash, forKey: "serverHash")
            coder.encode(openGroupMessageServerID, forKey: "openGroupMessageServerID")
            coder.encode(openGroupID, forKey: "openGroupID")
            coder.encode(isBackgroundPoll, forKey: "isBackgroundPoll")
            coder.encode(id, forKey: "id")
            coder.encode(failureCount, forKey: "failureCount")
        }
    }

    @objc(SNMessageSendJob)
    public final class MessageSendJob: NSObject, NSCoding {
        public let message: Message
        public let destination: Message.Destination
        public var id: String?
        public var failureCount: UInt = 0

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard let message = coder.decodeObject(forKey: "message") as! Message?,
                let rawDestination = coder.decodeObject(forKey: "destination") as! String?,
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
            self.message = message
            
            if let destString: String = MessageSendJob.process(rawDestination, type: "contact") {
                destination = .contact(publicKey: destString)
            }
            else if let destString: String = MessageSendJob.process(rawDestination, type: "closedGroup") {
                destination = .closedGroup(groupPublicKey: destString)
            }
            else if let destString: String = MessageSendJob.process(rawDestination, type: "openGroup") {
                let components = destString
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                
                guard components.count == 2, let channel = UInt64(components[0]) else { return nil }
                
                let server = components[1]
                destination = .openGroup(channel: channel, server: server)
            }
            else if let destString: String = MessageSendJob.process(rawDestination, type: "openGroupV2") {
                let components = destString
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                
                guard components.count == 2 else { return nil }
                
                let room = components[0]
                let server = components[1]
                destination = .openGroupV2(room: room, server: server)
            }
            else {
                return nil
            }
            
            self.id = id
            self.failureCount = ((coder.decodeObject(forKey: "failureCount") as? UInt) ?? 0)
        }

        public func encode(with coder: NSCoder) {
            coder.encode(message, forKey: "message")
            
            switch destination {
                case .contact(let publicKey):
                    coder.encode("contact(\(publicKey))", forKey: "destination")
                    
                case .closedGroup(let groupPublicKey):
                    coder.encode("closedGroup(\(groupPublicKey))", forKey: "destination")
                    
                case .openGroup(let channel, let server):
                    coder.encode("openGroup(\(channel), \(server))", forKey: "destination")
                    
                case .openGroupV2(let room, let server):
                    coder.encode("openGroupV2(\(room), \(server))", forKey: "destination")
            }
            
            coder.encode(id, forKey: "id")
            coder.encode(failureCount, forKey: "failureCount")
        }
        
        // MARK: - Convenience
        
        private static func process(_ value: String, type: String) -> String? {
            guard value.hasPrefix("\(type)(") else { return nil }
            guard value.hasSuffix(")") else { return nil }
            
            var updatedValue: String = value
            updatedValue.removeFirst("\(type)(".count)
            updatedValue.removeLast(")".count)
            
            return updatedValue
        }
    }
    
    @objc(AttachmentUploadJob)
    public final class AttachmentUploadJob: NSObject, NSCoding {
        public let attachmentID: String
        public let threadID: String
        public let message: Message
        public let messageSendJobID: String
        public var id: String?
        public var failureCount: UInt = 0
        
        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard
                let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
                let threadID = coder.decodeObject(forKey: "threadID") as! String?,
                let message = coder.decodeObject(forKey: "message") as! Message?,
                let messageSendJobID = coder.decodeObject(forKey: "messageSendJobID") as! String?,
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
            self.attachmentID = attachmentID
            self.threadID = threadID
            self.message = message
            self.messageSendJobID = messageSendJobID
            self.id = id
            self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
        }

        public func encode(with coder: NSCoder) {
            coder.encode(attachmentID, forKey: "attachmentID")
            coder.encode(threadID, forKey: "threadID")
            coder.encode(message, forKey: "message")
            coder.encode(messageSendJobID, forKey: "messageSendJobID")
            coder.encode(id, forKey: "id")
            coder.encode(failureCount, forKey: "failureCount")
        }
    }
    
    @objc(AttachmentDownloadJob)
    public final class AttachmentDownloadJob: NSObject, NSCoding {
        public let attachmentID: String
        public let tsMessageID: String
        public let threadID: String
        public var id: String?
        public var failureCount: UInt = 0
        public var isDeferred = false

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard
                let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
                let tsMessageID = coder.decodeObject(forKey: "tsIncomingMessageID") as! String?,
                let threadID = coder.decodeObject(forKey: "threadID") as! String?,
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
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
    }
}

@objc(SNJob)
public protocol _LegacyJob : NSCoding {
    var id: String? { get set }
    var failureCount: UInt { get set }

    static var collection: String { get }
    static var maxFailureCount: UInt { get }

    func execute()
}

// Note: Looks like Swift doesn't expose nested types well (in the `-Swift` header this was
// appearing with `SWIFT_CLASS_NAME("Contact")` which conflicts with the new type and has a
// different structure) as a result we cannot nest this cleanly
@objc(SNContact)
public class _LegacyContact: NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let sessionID: String
    /// The URL from which to fetch the contact's profile picture.
    @objc public var profilePictureURL: String?
    /// The file name of the contact's profile picture on local storage.
    @objc public var profilePictureFileName: String?
    /// The key with which the profile is encrypted.
    @objc public var profileEncryptionKey: OWSAES256Key?
    /// The ID of the thread associated with this contact.
    @objc public var threadID: String?
    /// This flag is used to determine whether we should auto-download files sent by this contact.
    @objc public var isTrusted = false
    /// This flag is used to determine whether message requests from this contact are approved
    @objc public var isApproved = false
    /// This flag is used to determine whether message requests from this contact are blocked
    @objc public var isBlocked = false {
        didSet {
            if isBlocked {
                hasBeenBlocked = true
            }
        }
    }
    /// This flag is used to determine whether this contact has approved the current users message request
    @objc public var didApproveMe = false
    /// This flag is used to determine whether this contact has ever been blocked (will be included in the config message if so)
    @objc public var hasBeenBlocked = false
    
    // MARK: Name
    /// The name of the contact. Use this whenever you need the "real", underlying name of a user (e.g. when sending a message).
    @objc public var name: String?
    /// The contact's nickname, if the user set one.
    @objc public var nickname: String?
    /// The name to display in the UI. For local use only.
    @objc public func displayName(for context: Context) -> String? {
        if let nickname = nickname { return nickname }
        switch context {
        case .regular: return name
        case .openGroup:
            // In open groups, where it's more likely that multiple users have the same name, we display a bit of the Session ID after
            // a user's display name for added context.
            guard let name = name else { return nil }
            let endIndex = sessionID.endIndex
            let cutoffIndex = sessionID.index(endIndex, offsetBy: -8)
            return "\(name) (...\(sessionID[cutoffIndex..<endIndex]))"
        }
    }
    
    // MARK: Context
    @objc(SNContactContext)
    public enum Context : Int {
        case regular, openGroup
    }
    
    // MARK: Initialization
    @objc public init(sessionID: String) {
        self.sessionID = sessionID
        super.init()
    }

    private override init() { preconditionFailure("Use init(sessionID:) instead.") }

    // MARK: Validation
    public var isValid: Bool {
        if profilePictureURL != nil { return (profileEncryptionKey != nil) }
        if profileEncryptionKey != nil { return (profilePictureURL != nil) }
        return true
    }
    
    // MARK: Coding
    
    public required init?(coder: NSCoder) {
        guard let sessionID = coder.decodeObject(forKey: "sessionID") as! String? else { return nil }
        self.sessionID = sessionID
        isTrusted = coder.decodeBool(forKey: "isTrusted")
        if let name = coder.decodeObject(forKey: "displayName") as! String? { self.name = name }
        if let nickname = coder.decodeObject(forKey: "nickname") as! String? { self.nickname = nickname }
        if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        if let profilePictureFileName = coder.decodeObject(forKey: "profilePictureFileName") as! String? { self.profilePictureFileName = profilePictureFileName }
        if let profileEncryptionKey = coder.decodeObject(forKey: "profilePictureEncryptionKey") as! OWSAES256Key? { self.profileEncryptionKey = profileEncryptionKey }
        if let threadID = coder.decodeObject(forKey: "threadID") as! String? { self.threadID = threadID }
        
        let isBlockedFlag: Bool = coder.decodeBool(forKey: "isBlocked")
        isApproved = coder.decodeBool(forKey: "isApproved")
        isBlocked = isBlockedFlag
        didApproveMe = coder.decodeBool(forKey: "didApproveMe")
        hasBeenBlocked = (coder.decodeBool(forKey: "hasBeenBlocked") || isBlockedFlag)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sessionID, forKey: "sessionID")
        coder.encode(name, forKey: "displayName")
        coder.encode(nickname, forKey: "nickname")
        coder.encode(profilePictureURL, forKey: "profilePictureURL")
        coder.encode(profilePictureFileName, forKey: "profilePictureFileName")
        coder.encode(profileEncryptionKey, forKey: "profilePictureEncryptionKey")
        coder.encode(threadID, forKey: "threadID")
        coder.encode(isTrusted, forKey: "isTrusted")
        coder.encode(isApproved, forKey: "isApproved")
        coder.encode(isBlocked, forKey: "isBlocked")
        coder.encode(didApproveMe, forKey: "didApproveMe")
        coder.encode(hasBeenBlocked, forKey: "hasBeenBlocked")
    }
    
    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? _LegacyContact else { return false }
        return sessionID == other.sessionID
    }

    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return sessionID.hash
    }

    // MARK: Description
    override public var description: String {
        nickname ?? name ?? sessionID
    }
    
    // MARK: Convenience
    @objc(contextForThread:)
    public static func context(for thread: TSThread) -> Context {
        return ((thread as? TSGroupThread)?.isOpenGroup == true) ? .openGroup : .regular

@objc(OWSDisappearingMessagesConfiguration)
public class _LegacyDisappearingMessagesConfiguration: MTLModel {
    public let uniqueId: String
    @objc public var isEnabled: Bool
    @objc public var durationSeconds: UInt32
    
    @objc public var durationIndex: UInt32 = 0
    @objc public var durationString: String?
    
    var originalDictionaryValue: [String: Any]?
    @objc public var isNewRecord: Bool = false
    
    @objc public static func defaultWith(_ threadId: String) -> Legacy.DisappearingMessagesConfiguration {
        return Legacy.DisappearingMessagesConfiguration(
            threadId: threadId,
            enabled: false,
            durationSeconds: (24 * 60 * 60)
        )
    }
    
    public static func fetch(uniqueId: String, transaction: YapDatabaseReadTransaction? = nil) -> Legacy.DisappearingMessagesConfiguration? {
        return nil
    }
    
    @objc public static func fetchObject(uniqueId: String) -> Legacy.DisappearingMessagesConfiguration? {
        return nil
    }
    
    @objc public static func fetchOrBuildDefault(threadId: String, transaction: YapDatabaseReadTransaction) -> Legacy.DisappearingMessagesConfiguration? {
        return defaultWith(threadId)
    }
    
    @objc public static var validDurationsSeconds: [UInt32] = []
    
    // MARK: - Initialization
    
    init(threadId: String, enabled: Bool, durationSeconds: UInt32) {
        self.uniqueId = threadId
        self.isEnabled = enabled
        self.durationSeconds = durationSeconds
        self.isNewRecord = true
        
        super.init()
    }
    
    required init(coder: NSCoder) {
        self.uniqueId = coder.decodeObject(forKey: "uniqueId") as! String
        self.isEnabled = coder.decodeObject(forKey: "enabled") as! Bool
        self.durationSeconds = coder.decodeObject(forKey: "durationSeconds") as! UInt32
        
        // Intentionally not calling 'super.init(coder:) here
        super.init()
    }
    
    required init(dictionary dictionaryValue: [String : Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }
    
    // MARK: - Dirty Tracking
    
    @objc public override static func storageBehaviorForProperty(withKey propertyKey: String) -> MTLPropertyStorage {
        // Don't persist transient properties
        if
            propertyKey == "TAG" ||
            propertyKey == "originalDictionaryValue" ||
            propertyKey == "newRecord"
        {
            return MTLPropertyStorageNone
        }
        
        return super.storageBehaviorForProperty(withKey: propertyKey)
    }
    
    @objc public var dictionaryValueDidChange: Bool {
        return false
    }
    
    @objc(saveWithTransaction:)
    public func save(with transaction: YapDatabaseReadWriteTransaction) {
        self.originalDictionaryValue = self.dictionaryValue
        self.isNewRecord = false
    }
}
