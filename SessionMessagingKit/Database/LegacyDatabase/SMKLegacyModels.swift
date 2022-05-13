// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Mantle
import Sodium
import YapDatabase
import SignalCoreKit
import SessionUtilitiesKit

public typealias SMKLegacy = Legacy

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
    internal static let attachmentsCollection = "TSAttachements"    // Note: This is how it was previously spelt
    internal static let outgoingReadReceiptManagerCollection = "kOutgoingReadReceiptManagerCollection"
    internal static let receivedMessageTimestampsCollection = "ReceivedMessageTimestampsCollection"
    internal static let receivedMessageTimestampsKey = "receivedMessageTimestamps"

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
    
    // MARK: - Types (and NSCoding)
    
    @objc(SNContact)
    public class _Contact: NSObject, NSCoding {
        @objc public let sessionID: String
        @objc public var profilePictureURL: String?
        @objc public var profilePictureFileName: String?
        @objc public var profileEncryptionKey: OWSAES256Key?
        @objc public var threadID: String?
        @objc public var isTrusted = false
        @objc public var isApproved = false
        @objc public var isBlocked = false
        @objc public var didApproveMe = false
        @objc public var hasBeenBlocked = false
        @objc public var name: String?
        @objc public var nickname: String?
        
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
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    @objc(OWSDisappearingMessagesConfiguration)
    internal class _DisappearingMessagesConfiguration: MTLModel {
        @objc public let uniqueId: String
        @objc public var isEnabled: Bool
        @objc public var durationSeconds: UInt32
        
        // MARK: - NSCoder
        
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
        
        override public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Visible/Control Message NSCoding
    
    /// Abstract base class for `VisibleMessage` and `ControlMessage`.
    @objc(SNMessage)
    internal class _Message: NSObject, NSCoding {
        internal var id: String?
        internal var threadID: String?
        internal var sentTimestamp: UInt64?
        internal var receivedTimestamp: UInt64?
        internal var recipient: String?
        internal var sender: String?
        internal var groupPublicKey: String?
        internal var openGroupServerMessageID: UInt64?
        internal var openGroupServerTimestamp: UInt64?
        internal var serverHash: String?

        // MARK: NSCoding
        
        public required init?(coder: NSCoder) {
            if let id = coder.decodeObject(forKey: "id") as! String? { self.id = id }
            if let threadID = coder.decodeObject(forKey: "threadID") as! String? { self.threadID = threadID }
            if let sentTimestamp = coder.decodeObject(forKey: "sentTimestamp") as! UInt64? { self.sentTimestamp = sentTimestamp }
            if let receivedTimestamp = coder.decodeObject(forKey: "receivedTimestamp") as! UInt64? { self.receivedTimestamp = receivedTimestamp }
            if let recipient = coder.decodeObject(forKey: "recipient") as! String? { self.recipient = recipient }
            if let sender = coder.decodeObject(forKey: "sender") as! String? { self.sender = sender }
            if let groupPublicKey = coder.decodeObject(forKey: "groupPublicKey") as! String? { self.groupPublicKey = groupPublicKey }
            if let openGroupServerMessageID = coder.decodeObject(forKey: "openGroupServerMessageID") as! UInt64? { self.openGroupServerMessageID = openGroupServerMessageID }
            if let openGroupServerTimestamp = coder.decodeObject(forKey: "openGroupServerTimestamp") as! UInt64? { self.openGroupServerTimestamp = openGroupServerTimestamp }
            if let serverHash = coder.decodeObject(forKey: "serverHash") as! String? { self.serverHash = serverHash }
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            let result: Message = (instance ?? Message())
            result.id = self.id
            result.threadId = self.threadID
            result.sentTimestamp = self.sentTimestamp
            result.receivedTimestamp = self.receivedTimestamp
            result.recipient = self.recipient
            result.sender = self.sender
            result.groupPublicKey = self.groupPublicKey
            result.openGroupServerMessageId = self.openGroupServerMessageID
            result.openGroupServerTimestamp = self.openGroupServerTimestamp
            result.serverHash = self.serverHash
            
            return result
        }
    }

    @objc(SNVisibleMessage)
    internal final class _VisibleMessage: _Message {
        internal var syncTarget: String?
        internal var text: String?
        internal var attachmentIDs: [String] = []
        internal var quote: _Quote?
        internal var linkPreview: _LinkPreview?
        internal var profile: _Profile?
        internal var openGroupInvitation: _OpenGroupInvitation?

        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            
            if let syncTarget = coder.decodeObject(forKey: "syncTarget") as! String? { self.syncTarget = syncTarget }
            if let text = coder.decodeObject(forKey: "body") as! String? { self.text = text }
            if let attachmentIDs = coder.decodeObject(forKey: "attachments") as! [String]? { self.attachmentIDs = attachmentIDs }
            if let quote = coder.decodeObject(forKey: "quote") as! _Quote? { self.quote = quote }
            if let linkPreview = coder.decodeObject(forKey: "linkPreview") as! _LinkPreview? { self.linkPreview = linkPreview }
            if let profile = coder.decodeObject(forKey: "profile") as! _Profile? { self.profile = profile }
            if let openGroupInvitation = coder.decodeObject(forKey: "openGroupInvitation") as! _OpenGroupInvitation? { self.openGroupInvitation = openGroupInvitation }
        }
        
        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                VisibleMessage(
                    syncTarget: syncTarget,
                    text: text,
                    attachmentIds: attachmentIDs,
                    quote: quote?.toNonLegacy(),
                    linkPreview: linkPreview?.toNonLegacy(),
                    profile: profile?.toNonLegacy(),
                    openGroupInvitation: openGroupInvitation?.toNonLegacy()
                )
            )
        }
    }
    
    @objc(SNQuote)
    internal class _Quote: NSObject, NSCoding {
        internal var timestamp: UInt64?
        internal var publicKey: String?
        internal var text: String?
        internal var attachmentID: String?
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            if let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? { self.timestamp = timestamp }
            if let publicKey = coder.decodeObject(forKey: "authorId") as! String? { self.publicKey = publicKey }
            if let text = coder.decodeObject(forKey: "body") as! String? { self.text = text }
            if let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String? { self.attachmentID = attachmentID }
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy() -> VisibleMessage.VMQuote {
            return VisibleMessage.VMQuote(
                timestamp: (timestamp ?? 0),
                publicKey: (publicKey ?? ""),
                text: text,
                attachmentId: attachmentID
            )
        }
    }
    
    @objc(SNLinkPreview)
    internal class _LinkPreview: NSObject, NSCoding {
        internal var title: String?
        internal var url: String?
        internal var attachmentID: String?
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            if let title = coder.decodeObject(forKey: "title") as! String? { self.title = title }
            if let url = coder.decodeObject(forKey: "urlString") as! String? { self.url = url }
            if let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String? { self.attachmentID = attachmentID }
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy() -> VisibleMessage.VMLinkPreview {
            return VisibleMessage.VMLinkPreview(
                title: title,
                url: (url ?? ""),
                attachmentId: attachmentID
            )
        }
    }
    
    @objc(SNProfile)
    internal class _Profile: NSObject, NSCoding {
        internal var displayName: String?
        internal var profileKey: Data?
        internal var profilePictureURL: String?
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            if let displayName = coder.decodeObject(forKey: "displayName") as! String? { self.displayName = displayName }
            if let profileKey = coder.decodeObject(forKey: "profileKey") as! Data? { self.profileKey = profileKey }
            if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy() -> VisibleMessage.VMProfile {
            return VisibleMessage.VMProfile(
                displayName: (displayName ?? ""),
                profileKey: profileKey,
                profilePictureUrl: profilePictureURL
            )
        }
    }
    
    @objc(SNOpenGroupInvitation)
    internal class _OpenGroupInvitation: NSObject, NSCoding {
        internal var name: String?
        internal var url: String?
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            if let name = coder.decodeObject(forKey: "name") as! String? { self.name = name }
            if let url = coder.decodeObject(forKey: "url") as! String? { self.url = url }
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy() -> VisibleMessage.VMOpenGroupInvitation {
            return VisibleMessage.VMOpenGroupInvitation(
                name: (name ?? ""),
                url: (url ?? "")
            )
        }
    }
    
    @objc(SNControlMessage)
    internal class _ControlMessage: _Message {}
    
    @objc(SNReadReceipt)
    internal final class _ReadReceipt: _ControlMessage {
        internal var timestamps: [UInt64]?

        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            if let timestamps = coder.decodeObject(forKey: "messageTimestamps") as! [UInt64]? { self.timestamps = timestamps }
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                ReadReceipt(
                    timestamps: (timestamps ?? [])
                )
            )
        }
    }
    
    @objc(SNTypingIndicator)
    internal final class _TypingIndicator: _ControlMessage {
        public var rawKind: Int?

        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            
            self.rawKind = coder.decodeObject(forKey: "action") as! Int?
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                TypingIndicator(
                    kind: TypingIndicator.Kind(
                        rawValue: (rawKind ?? TypingIndicator.Kind.stopped.rawValue)
                    )
                    .defaulting(to: .stopped)
                )
            )
        }
    }

    @objc(SNClosedGroupControlMessage)
    internal final class _ClosedGroupControlMessage: _ControlMessage {
        internal var rawKind: String?
        
        internal var publicKey: Data?
        internal var wrappers: [_KeyPairWrapper]?
        internal var name: String?
        internal var encryptionKeyPair: SUKLegacy.KeyPair?
        internal var members: [Data]?
        internal var admins: [Data]?
        internal var expirationTimer: UInt32

        // MARK: - Key Pair Wrapper
        
        @objc(SNKeyPairWrapper)
        internal final class _KeyPairWrapper: NSObject, NSCoding {
            internal var publicKey: String?
            internal var encryptedKeyPair: Data?
            
            // MARK: - NSCoding

            public required init?(coder: NSCoder) {
                if let publicKey = coder.decodeObject(forKey: "publicKey") as! String? { self.publicKey = publicKey }
                if let encryptedKeyPair = coder.decodeObject(forKey: "encryptedKeyPair") as! Data? { self.encryptedKeyPair = encryptedKeyPair }
            }

            public func encode(with coder: NSCoder) {
                fatalError("encode(with:) should never be called for legacy types")
            }
        }
        
        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            self.rawKind = coder.decodeObject(forKey: "kind") as? String
            
            self.publicKey = coder.decodeObject(forKey: "publicKey") as? Data
            self.wrappers = coder.decodeObject(forKey: "wrappers") as? [_KeyPairWrapper]
            self.name = coder.decodeObject(forKey: "name") as? String
            self.encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as? SUKLegacy.KeyPair
            self.members = coder.decodeObject(forKey: "members") as? [Data]
            self.admins = coder.decodeObject(forKey: "admins") as? [Data]
            self.expirationTimer = (coder.decodeObject(forKey: "expirationTimer") as? UInt32 ?? 0)
            
            super.init(coder: coder)
        }
        
        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                ClosedGroupControlMessage(
                    kind: try {
                        switch rawKind {
                            case "new":
                                guard
                                    let publicKey: Data = self.publicKey,
                                    let name: String = self.name,
                                    let encryptionKeyPair: SUKLegacy.KeyPair = self.encryptionKeyPair,
                                    let members: [Data] = self.members,
                                    let admins: [Data] = self.admins
                                else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw GRDBStorageError.migrationFailed
                                }
                                
                                return .new(
                                    publicKey: publicKey,
                                    name: name,
                                    encryptionKeyPair: Box.KeyPair(
                                        publicKey: encryptionKeyPair.publicKey.bytes,
                                        secretKey: encryptionKeyPair.privateKey.bytes
                                    ),
                                    members: members,
                                    admins: admins,
                                    expirationTimer: self.expirationTimer
                                )
                                
                            case "encryptionKeyPair":
                                guard let wrappers: [_KeyPairWrapper] = self.wrappers else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw GRDBStorageError.migrationFailed
                                }
                                
                                return .encryptionKeyPair(
                                    publicKey: publicKey,
                                    wrappers: try wrappers.map { wrapper in
                                        guard
                                            let publicKey: String = wrapper.publicKey,
                                            let encryptedKeyPair: Data = wrapper.encryptedKeyPair
                                        else {
                                            SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                            throw GRDBStorageError.migrationFailed
                                        }

                                        return SessionMessagingKit.ClosedGroupControlMessage.KeyPairWrapper(
                                            publicKey: publicKey,
                                            encryptedKeyPair: encryptedKeyPair
                                        )
                                    }
                                )
                                
                            case "nameChange":
                                guard let name: String = self.name else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw GRDBStorageError.migrationFailed
                                }
                                
                                return .nameChange(
                                    name: name
                                )
                                
                            case "membersAdded":
                                guard let members: [Data] = self.members else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw GRDBStorageError.migrationFailed
                                }
                                
                                return .membersAdded(members: members)
                                
                            case "membersRemoved":
                                guard let members: [Data] = self.members else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw GRDBStorageError.migrationFailed
                                }
                                
                                return .membersRemoved(members: members)
                                
                            case "memberLeft": return .memberLeft
                            case "encryptionKeyPairRequest": return .encryptionKeyPairRequest
                            default: throw GRDBStorageError.migrationFailed
                        }
                    }()
                )
            )
        }
    }
    
    @objc(SNDataExtractionNotification)
    internal final class _DataExtractionNotification: _ControlMessage {
        internal let rawKind: String?
        internal let timestamp: UInt64?
        
        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            self.rawKind = coder.decodeObject(forKey: "kind") as? String
            self.timestamp = coder.decodeObject(forKey: "timestamp") as? UInt64
            
            super.init(coder: coder)
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                DataExtractionNotification(
                    kind: try {
                        switch rawKind {
                            case "screenshot": return .screenshot
                            case "mediaSaved":
                                guard let timestamp: UInt64 = self.timestamp else {
                                    SNLog("[Migration Error] Unable to decode Legacy DataExtractionNotification")
                                    throw GRDBStorageError.migrationFailed
                                }
                                
                                return .mediaSaved(timestamp: timestamp)
                                
                            default: throw GRDBStorageError.migrationFailed
                        }
                    }()
                )
            )
        }
    }
    
    @objc(SNExpirationTimerUpdate)
    internal final class _ExpirationTimerUpdate: _ControlMessage {
        internal var syncTarget: String?
        internal var duration: UInt32?
        
        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            if let syncTarget = coder.decodeObject(forKey: "syncTarget") as! String? { self.syncTarget = syncTarget }
            if let duration = coder.decodeObject(forKey: "durationSeconds") as! UInt32? { self.duration = duration }
        }
        
        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                ExpirationTimerUpdate(
                    syncTarget: syncTarget,
                    duration: (duration ?? 0)
                )
            )
        }
    }
    
    @objc(SNConfigurationMessage)
    internal final class _ConfigurationMessage: _ControlMessage {
        internal var closedGroups: Set<_CMClosedGroup> = []
        internal var openGroups: Set<String> = []
        internal var displayName: String?
        internal var profilePictureURL: String?
        internal var profileKey: Data?
        internal var contacts: Set<_CMContact> = []
        
        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            if let closedGroups = coder.decodeObject(forKey: "closedGroups") as! Set<_CMClosedGroup>? { self.closedGroups = closedGroups }
            if let openGroups = coder.decodeObject(forKey: "openGroups") as! Set<String>? { self.openGroups = openGroups }
            if let displayName = coder.decodeObject(forKey: "displayName") as! String? { self.displayName = displayName }
            if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
            if let profileKey = coder.decodeObject(forKey: "profileKey") as! Data? { self.profileKey = profileKey }
            if let contacts = coder.decodeObject(forKey: "contacts") as! Set<_CMContact>? { self.contacts = contacts }
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                ConfigurationMessage(
                    displayName: displayName,
                    profilePictureUrl: profilePictureURL,
                    profileKey: profileKey,
                    closedGroups: closedGroups
                        .map { $0.toNonLegacy() }
                        .asSet(),
                    openGroups: openGroups,
                    contacts: contacts
                        .map { $0.toNonLegacy() }
                        .asSet()
                )
            )
        }
    }

    @objc(CMClosedGroup)
    internal final class _CMClosedGroup: NSObject, NSCoding {
        internal let publicKey: String
        internal let name: String
        internal let encryptionKeyPair: SUKLegacy.KeyPair
        internal let members: Set<String>
        internal let admins: Set<String>
        internal let expirationTimer: UInt32
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            guard
                let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let name = coder.decodeObject(forKey: "name") as! String?,
                let encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as! SUKLegacy.KeyPair?,
                let members = coder.decodeObject(forKey: "members") as! Set<String>?,
                let admins = coder.decodeObject(forKey: "admins") as! Set<String>?
            else { return nil }
            
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
            self.expirationTimer = (coder.decodeObject(forKey: "expirationTimer") as? UInt32 ?? 0)
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy() -> ConfigurationMessage.CMClosedGroup {
            return ConfigurationMessage.CMClosedGroup(
                publicKey: publicKey,
                name: name,
                encryptionKeyPublicKey: encryptionKeyPair.publicKey,
                encryptionKeySecretKey: encryptionKeyPair.privateKey,
                members: members,
                admins: admins,
                expirationTimer: expirationTimer
            )
        }
    }

    @objc(SNConfigurationMessageContact)
    internal final class _CMContact: NSObject, NSCoding {
        internal var publicKey: String?
        internal var displayName: String?
        internal var profilePictureURL: String?
        internal var profileKey: Data?
        
        internal var hasIsApproved: Bool
        internal var isApproved: Bool
        internal var hasIsBlocked: Bool
        internal var isBlocked: Bool
        internal var hasDidApproveMe: Bool
        internal var didApproveMe: Bool
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            guard
                let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let displayName = coder.decodeObject(forKey: "displayName") as! String?
            else { return nil }
            
            self.publicKey = publicKey
            self.displayName = displayName
            self.profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String?
            self.profileKey = coder.decodeObject(forKey: "profileKey") as! Data?
            self.hasIsApproved = (coder.decodeObject(forKey: "hasIsApproved") as? Bool ?? false)
            self.isApproved = (coder.decodeObject(forKey: "isApproved") as? Bool ?? false)
            self.hasIsBlocked = (coder.decodeObject(forKey: "hasIsBlocked") as? Bool ?? false)
            self.isBlocked = (coder.decodeObject(forKey: "isBlocked") as? Bool ?? false)
            self.hasDidApproveMe = (coder.decodeObject(forKey: "hasDidApproveMe") as? Bool ?? false)
            self.didApproveMe = (coder.decodeObject(forKey: "didApproveMe") as? Bool ?? false)
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        internal func toNonLegacy() -> ConfigurationMessage.CMContact {
            return ConfigurationMessage.CMContact(
                publicKey: publicKey,
                displayName: displayName,
                profilePictureUrl: profilePictureURL,
                profileKey: profileKey,
                hasIsApproved: hasIsApproved,
                isApproved: isApproved,
                hasIsBlocked: hasIsBlocked,
                isBlocked: isBlocked,
                hasDidApproveMe: hasDidApproveMe,
                didApproveMe: didApproveMe
            )
        }
    }
    
    @objc(SNUnsendRequest)
    internal final class _UnsendRequest: _ControlMessage {
        internal var timestamp: UInt64?
        internal var author: String?
        
        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            
            self.timestamp = coder.decodeObject(forKey: "timestamp") as? UInt64
            self.author = coder.decodeObject(forKey: "author") as? String
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                UnsendRequest(
                    timestamp: (timestamp ?? 0),
                    author: (author ?? "")
                )
            )
        }
    }
    
    @objc(SNMessageRequestResponse)
    internal final class _MessageRequestResponse: _ControlMessage {
        internal var isApproved: Bool
        
        // MARK: - NSCoding

        public required init?(coder: NSCoder) {
            self.isApproved = coder.decodeBool(forKey: "isApproved")
            
            super.init(coder: coder)
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                MessageRequestResponse(
                    isApproved: isApproved
                )
            )
        }
    }

    // MARK: - Attachments
    
    @objc(TSAttachment)
    internal class _Attachment: NSObject, NSCoding {
        @objc(TSAttachmentType)
        public enum _AttachmentType: Int {
            case `default`
            case voiceMessage
        }
        
        @objc public var serverId: UInt64
        @objc public var encryptionKey: Data?
        @objc public var contentType: String
        @objc public var isDownloaded: Bool
        @objc public var attachmentType: _AttachmentType
        @objc public var downloadURL: String
        @objc public var byteCount: UInt32
        @objc public var sourceFilename: String?
        @objc public var caption: String?
        @objc public var albumMessageId: String?
        
        public var isImage: Bool { return MIMETypeUtil.isImage(contentType) }
        public var isVideo: Bool { return MIMETypeUtil.isVideo(contentType) }
        public var isAudio: Bool { return MIMETypeUtil.isAudio(contentType) }
        public var isAnimated: Bool { return MIMETypeUtil.isAnimated(contentType) }
        
        public var isVisualMedia: Bool { isImage || isVideo || isAnimated }
        
        // MARK: - NSCoder
        
        public required init(coder: NSCoder) {
            self.serverId = coder.decodeObject(forKey: "serverId") as! UInt64
            self.encryptionKey = coder.decodeObject(forKey: "encryptionKey") as? Data
            self.contentType = coder.decodeObject(forKey: "contentType") as! String
            self.isDownloaded = (coder.decodeObject(forKey: "isDownloaded") as? Bool == true)
            self.attachmentType = _AttachmentType(
                rawValue: (coder.decodeObject(forKey: "attachmentType") as! NSNumber).intValue
            ).defaulting(to: .default)
            self.downloadURL = (coder.decodeObject(forKey: "downloadURL") as? String ?? "")
            self.byteCount = coder.decodeObject(forKey: "byteCount") as! UInt32
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    @objc(TSAttachmentPointer)
    internal class _AttachmentPointer: _Attachment {
        @objc(TSAttachmentPointerState)
        public enum _State: Int {
            case enqueued
            case downloading
            case failed
        }
        
        @objc public var state: _State
        @objc public var mostRecentFailureLocalizedText: String?
        @objc public var digest: Data?
        @objc public var mediaSize: CGSize
        @objc public var lazyRestoreFragmentId: String?
        
        // MARK: - NSCoder
        
        public required init(coder: NSCoder) {
            self.state = _State(
                rawValue: coder.decodeObject(forKey: "state") as! Int
            ).defaulting(to: .failed)
            self.mostRecentFailureLocalizedText = coder.decodeObject(forKey: "mostRecentFailureLocalizedText") as? String
            self.digest = coder.decodeObject(forKey: "digest") as? Data
            self.mediaSize = coder.decodeObject(forKey: "mediaSize") as! CGSize
            self.lazyRestoreFragmentId = coder.decodeObject(forKey: "lazyRestoreFragmentId") as? String
            
            super.init(coder: coder)
        }
        
        override public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    @objc(TSAttachmentStream)
    internal class _AttachmentStream: _Attachment {
        @objc public var digest: Data?
        @objc public var isUploaded: Bool
        @objc public var creationTimestamp: Date
        @objc public var localRelativeFilePath: String?
        @objc public var cachedImageWidth: NSNumber?
        @objc public var cachedImageHeight: NSNumber?
        @objc public var cachedAudioDurationSeconds: NSNumber?
        @objc public var isValidImageCached: NSNumber?
        @objc public var isValidVideoCached: NSNumber?
        
        public var isValidImage: Bool { return (isValidImageCached?.boolValue == true) }
        public var isValidVideo: Bool { return (isValidVideoCached?.boolValue == true) }
        
        public var isValidVisualMedia: Bool {
            if self.isImage && self.isValidImage { return true }
            if self.isVideo && self.isValidVideo { return true }
            if self.isAnimated && self.isValidImage { return true }
            
            return false
        }
        
        // MARK: - NSCoder
        
        public required init(coder: NSCoder) {
            self.digest = coder.decodeObject(forKey: "digest") as? Data
            self.isUploaded = (coder.decodeObject(forKey: "isUploaded") as? Bool == true)
            self.creationTimestamp = coder.decodeObject(forKey: "creationTimestamp") as! Date
            self.localRelativeFilePath = coder.decodeObject(forKey: "localRelativeFilePath") as? String
            self.cachedImageWidth = coder.decodeObject(forKey: "cachedImageWidth") as? NSNumber
            self.cachedImageHeight = coder.decodeObject(forKey: "cachedImageHeight") as? NSNumber
            self.cachedAudioDurationSeconds = coder.decodeObject(forKey: "cachedAudioDurationSeconds") as? NSNumber
            self.isValidImageCached = coder.decodeObject(forKey: "isValidImageCached") as? NSNumber
            self.isValidVideoCached = coder.decodeObject(forKey: "isValidVideoCached") as? NSNumber
            
            super.init(coder: coder)
        }
        
        override public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }

    @objc(NotifyPNServerJob)
    internal final class _NotifyPNServerJob: NSObject, NSCoding {
        @objc(SnodeMessage)
        internal final class _SnodeMessage: NSObject, NSCoding {
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
                fatalError("encode(with:) should never be called for legacy types")
            }
        }
        
        public let message: _SnodeMessage
        public var id: String?
        public var failureCount: UInt = 0

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard
                let message = coder.decodeObject(forKey: "message") as! _SnodeMessage?,
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
            self.message = message
            self.id = id
            self.failureCount = ((coder.decodeObject(forKey: "failureCount") as? UInt) ?? 0)
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }

    @objc(MessageReceiveJob)
    public final class _MessageReceiveJob: NSObject, NSCoding {
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
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
            self.data = data
            self.serverHash = coder.decodeObject(forKey: "serverHash") as! String?
            self.openGroupMessageServerID = coder.decodeObject(forKey: "openGroupMessageServerID") as! UInt64?
            self.openGroupID = coder.decodeObject(forKey: "openGroupID") as! String?
            // Note: This behaviour is changed from the old code but the 'isBackgroundPoll' is only set
            // when getting messages from the 'BackgroundPoller' class and since we likely want to process
            // these new messages immediately it should be fine to do this (this value seemed to be missing
            // in some cases which resulted in the 'Legacy.MessageReceiveJob' failing to parse)
            self.isBackgroundPoll = ((coder.decodeObject(forKey: "isBackgroundPoll") as? Bool) ?? false)
            self.id = id
            self.failureCount = ((coder.decodeObject(forKey: "failureCount") as? UInt) ?? 0)
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }

    @objc(SNMessageSendJob)
    internal final class _MessageSendJob: NSObject, NSCoding {
        internal let message: _Message
        internal let destination: Message.Destination
        internal var id: String?
        internal var failureCount: UInt = 0

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard let message = coder.decodeObject(forKey: "message") as! _Message?,
                let rawDestination = coder.decodeObject(forKey: "destination") as! String?,
                let id = coder.decodeObject(forKey: "id") as! String?
            else { return nil }
            
            self.message = message
            
            if let destString: String = _MessageSendJob.process(rawDestination, type: "contact") {
                destination = .contact(publicKey: destString)
            }
            else if let destString: String = _MessageSendJob.process(rawDestination, type: "closedGroup") {
                destination = .closedGroup(groupPublicKey: destString)
            }
            else if let destString: String = _MessageSendJob.process(rawDestination, type: "openGroup") {
                let components = destString
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                
                guard components.count == 2, let channel = UInt64(components[0]) else { return nil }
                
                let server = components[1]
                destination = .openGroup(channel: channel, server: server)
            }
            else if let destString: String = _MessageSendJob.process(rawDestination, type: "openGroupV2") {
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
            fatalError("encode(with:) should never be called for legacy types")
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
    internal final class _AttachmentUploadJob: NSObject, NSCoding {
        internal let attachmentID: String
        internal let threadID: String
        internal let message: _Message
        internal let messageSendJobID: String
        internal var id: String?
        internal var failureCount: UInt = 0
        
        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            guard
                let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
                let threadID = coder.decodeObject(forKey: "threadID") as! String?,
                let message = coder.decodeObject(forKey: "message") as! _Message?,
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
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    @objc(AttachmentDownloadJob)
    public final class _AttachmentDownloadJob: NSObject, NSCoding {
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
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    public final class _DisappearingConfigurationUpdateInfoMessage: TSInfoMessage {
        // Note: Due to how Mantle works we need to set default values for these as the 'init(dictionary:)'
        // method doesn't actually get values for them but the must be set before calling a super.init method
        // so this allows us to work around the behaviour until 'init(coder:)' method completes it's super call
        var createdByRemoteName: String?
        var configurationDurationSeconds: UInt32 = 0
        var configurationIsEnabled: Bool = false
        
        // MARK: - Coding
        
        public required init(coder: NSCoder) {
            super.init(coder: coder)
            
            self.createdByRemoteName = coder.decodeObject(forKey: "createdByRemoteName") as? String
            self.configurationDurationSeconds = ((coder.decodeObject(forKey: "configurationDurationSeconds") as? UInt32) ?? 0)
            self.configurationIsEnabled = ((coder.decodeObject(forKey: "configurationIsEnabled") as? Bool) ?? false)
        }
        
        required init(dictionary dictionaryValue: [String : Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
        
        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
}
