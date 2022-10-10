// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import YapDatabase
import SignalCoreKit
import SessionUtilitiesKit

public enum SMKLegacy {
    // MARK: - Collections and Keys
    
    internal static let contactThreadPrefix = "c"
    internal static let groupThreadPrefix = "g"
    internal static let closedGroupIdPrefix = "__textsecure_group__!"
    internal static let openGroupIdPrefix = "__loki_public_chat_group__!"
    internal static let closedGroupKeyPairPrefix = "SNClosedGroupEncryptionKeyPairCollection-"
    
    internal static let databaseMigrationCollection = "OWSDatabaseMigration"
    
    public static let contactCollection = "LokiContactCollection"
    public static let threadCollection = "TSThread"
    internal static let disappearingMessagesCollection = "OWSDisappearingMessagesConfiguration"
    
    internal static let closedGroupFormationTimestampCollection = "SNClosedGroupFormationTimestampCollection"
    internal static let closedGroupZombieMembersCollection = "SNClosedGroupZombieMembersCollection"
    
    internal static let openGroupCollection = "SNOpenGroupCollection"
    internal static let openGroupUserCountCollection = "SNOpenGroupUserCountCollection"
    internal static let openGroupImageCollection = "SNOpenGroupImageCollection"
    
    public static let messageDatabaseViewExtensionName = "TSMessageDatabaseViewExtensionName_Monotonic"
    internal static let interactionCollection = "TSInteraction"
    internal static let attachmentsCollection = "TSAttachements"    // Note: This is how it was previously spelt
    internal static let outgoingReadReceiptManagerCollection = "kOutgoingReadReceiptManagerCollection"
    internal static let receivedMessageTimestampsCollection = "ReceivedMessageTimestampsCollection"
    internal static let receivedMessageTimestampsKey = "receivedMessageTimestamps"
    internal static let receivedCallsCollection = "LokiReceivedCallsCollection"

    internal static let notifyPushServerJobCollection = "NotifyPNServerJobCollection"
    internal static let messageReceiveJobCollection = "MessageReceiveJobCollection"
    internal static let messageSendJobCollection = "MessageSendJobCollection"
    internal static let attachmentUploadJobCollection = "AttachmentUploadJobCollection"
    internal static let attachmentDownloadJobCollection = "AttachmentDownloadJobCollection"
    
    internal static let blockListCollection: String = "kOWSBlockingManager_BlockedPhoneNumbersCollection"
    internal static let blockedPhoneNumbersKey: String = "kOWSBlockingManager_BlockedPhoneNumbersKey"
    
    // Preferences
    
    internal static let preferencesCollection = "SignalPreferences"
    internal static let additionalPreferencesCollection = "SSKPreferences"
    internal static let preferencesKeyLastRecordedPushToken = "LastRecordedPushToken"
    internal static let preferencesKeyLastRecordedVoipToken = "LastRecordedVoipToken"
    internal static let preferencesKeyAreLinkPreviewsEnabled = "areLinkPreviewsEnabled"
    internal static let preferencesKeyAreCallsEnabled = "areCallsEnabled"
    internal static let preferencesKeyNotificationPreviewType = "preferencesKeyNotificationPreviewType"
    internal static let preferencesKeyNotificationSoundInForeground = "NotificationSoundInForeground"
    internal static let preferencesKeyHasSavedThreadKey = "hasSavedThread"
    internal static let preferencesKeyHasSentAMessageKey = "User has sent a message"
    internal static let preferencesKeyIsReadyForAppExtensions = "isReadyForAppExtensions_5"
    
    internal static let readReceiptManagerCollection = "OWSReadReceiptManagerCollection"
    internal static let readReceiptManagerAreReadReceiptsEnabled = "areReadReceiptsEnabled"
    
    internal static let typingIndicatorsCollection = "TypingIndicators"
    internal static let typingIndicatorsEnabledKey = "kDatabaseKey_TypingIndicatorsEnabled"
    
    internal static let screenLockCollection = "OWSScreenLock_Collection"
    internal static let screenLockIsScreenLockEnabledKey = "OWSScreenLock_Key_IsScreenLockEnabled"
    internal static let screenLockScreenLockTimeoutSecondsKey = "OWSScreenLock_Key_ScreenLockTimeoutSeconds"
    
    internal static let soundsStorageNotificationCollection = "kOWSSoundsStorageNotificationCollection"
    internal static let soundsGlobalNotificationKey = "kOWSSoundsStorageGlobalNotificationKey"
    
    internal static let userDefaultsHasHiddenMessageRequests = "hasHiddenMessageRequests"
    internal static let userDefaultsHasViewedSeedKey = "hasViewedSeed"
    
    // MARK: - DatabaseMigration
    
    public enum _DBMigration: String {
        case contactsMigration = "001"                  // Handled during contact migration
        case messageRequestsMigration = "002"           // Handled during contact migration
        case openGroupServerIdLookupMigration = "003"   // Ignored (creates a lookup table, replaced with an index)
        case blockingManagerRemovalMigration = "004"    // Handled during contact migration
        case sogsV4Migration = "005"                    // Ignored (deletes unused data, replaced by not migrating)
    }
    
    // MARK: - Contact
    
    @objc(SNContact)
    public class _Contact: NSObject, NSCoding {
        public let sessionID: String
        public var profilePictureURL: String?
        public var profilePictureFileName: String?
        public var profileEncryptionKey: OWSAES256Key?
        public var threadID: String?
        public var isTrusted = false
        public var isApproved = false
        public var isBlocked = false
        public var didApproveMe = false
        public var hasBeenBlocked = false
        public var name: String?
        public var nickname: String?
        
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
    
    // MARK: - Message
    
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
        internal var openGroupServerTimestamp: UInt64?  // Not used for anything
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
            result.serverHash = self.serverHash
            
            return result
        }
    }
    
    // MARK: - Visible Message

    @objc(SNVisibleMessage)
    internal final class _VisibleMessage: _Message {
        internal var syncTarget: String?
        internal var text: String?
        internal var attachmentIDs: [String] = []
        internal var quote: _Quote?
        internal var linkPreview: _LinkPreview?
        internal var profile: _Profile?
        internal var openGroupInvitation: _OpenGroupInvitation?

        // MARK: NSCoding
        
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
    
    // MARK: - Quote
    
    @objc(SNQuote)
    internal class _Quote: NSObject, NSCoding {
        internal var timestamp: UInt64?
        internal var publicKey: String?
        internal var text: String?
        internal var attachmentID: String?
        
        // MARK: NSCoding

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
    
    // MARK: - Link Preview
    
    @objc(SNLinkPreview)
    internal class _LinkPreview: NSObject, NSCoding {
        internal var title: String?
        internal var url: String?
        internal var attachmentID: String?
        
        // MARK: NSCoding

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
    
    // MARK: - Profile
    
    @objc(SNProfile)
    internal class _Profile: NSObject, NSCoding {
        internal var displayName: String?
        internal var profileKey: Data?
        internal var profilePictureURL: String?
        
        // MARK: NSCoding

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
    
    // MARK: - Open Group Invitation
    
    @objc(SNOpenGroupInvitation)
    internal class _OpenGroupInvitation: NSObject, NSCoding {
        internal var name: String?
        internal var url: String?
        
        // MARK: NSCoding

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
    
    // MARK: - Control Message
    
    @objc(SNControlMessage)
    internal class _ControlMessage: _Message {}
    
    // MARK: - Read Receipt
    
    @objc(SNReadReceipt)
    internal final class _ReadReceipt: _ControlMessage {
        internal var timestamps: [UInt64]?

        // MARK: NSCoding
        
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
    
    // MARK: - Typing Indicator
    
    @objc(SNTypingIndicator)
    internal final class _TypingIndicator: _ControlMessage {
        public var rawKind: Int?

        // MARK: NSCoding
        
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
    
    // MARK: - Closed Group Control Message

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

        // MARK: Key Pair Wrapper
        
        @objc(SNKeyPairWrapper)
        internal final class _KeyPairWrapper: NSObject, NSCoding {
            internal var publicKey: String?
            internal var encryptedKeyPair: Data?
            
            // MARK: NSCoding

            public required init?(coder: NSCoder) {
                if let publicKey = coder.decodeObject(forKey: "publicKey") as! String? { self.publicKey = publicKey }
                if let encryptedKeyPair = coder.decodeObject(forKey: "encryptedKeyPair") as! Data? { self.encryptedKeyPair = encryptedKeyPair }
            }

            public func encode(with coder: NSCoder) {
                fatalError("encode(with:) should never be called for legacy types")
            }
        }
        
        // MARK: NSCoding
        
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
                                    throw StorageError.migrationFailed
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
                                    throw StorageError.migrationFailed
                                }
                                
                                return .encryptionKeyPair(
                                    publicKey: publicKey,
                                    wrappers: try wrappers.map { wrapper in
                                        guard
                                            let publicKey: String = wrapper.publicKey,
                                            let encryptedKeyPair: Data = wrapper.encryptedKeyPair
                                        else {
                                            SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                            throw StorageError.migrationFailed
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
                                    throw StorageError.migrationFailed
                                }
                                
                                return .nameChange(
                                    name: name
                                )
                                
                            case "membersAdded":
                                guard let members: [Data] = self.members else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw StorageError.migrationFailed
                                }
                                
                                return .membersAdded(members: members)
                                
                            case "membersRemoved":
                                guard let members: [Data] = self.members else {
                                    SNLog("[Migration Error] Unable to decode Legacy ClosedGroupControlMessage")
                                    throw StorageError.migrationFailed
                                }
                                
                                return .membersRemoved(members: members)
                                
                            case "memberLeft": return .memberLeft
                            case "encryptionKeyPairRequest": return .encryptionKeyPairRequest
                            default: throw StorageError.migrationFailed
                        }
                    }()
                )
            )
        }
    }
    
    // MARK: - Data Extraction Notification
    
    @objc(SNDataExtractionNotification)
    internal final class _DataExtractionNotification: _ControlMessage {
        internal let rawKind: String?
        internal let timestamp: UInt64?
        
        // MARK: NSCoding
        
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
                                    throw StorageError.migrationFailed
                                }
                                
                                return .mediaSaved(timestamp: timestamp)
                                
                            default: throw StorageError.migrationFailed
                        }
                    }()
                )
            )
        }
    }
    
    // MARK: - Expiration Timer Update
    
    @objc(SNExpirationTimerUpdate)
    internal final class _ExpirationTimerUpdate: _ControlMessage {
        internal var syncTarget: String?
        internal var duration: UInt32?
        
        // MARK: NSCoding
        
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
    
    // MARK: - Configuration Message
    
    @objc(SNConfigurationMessage)
    internal final class _ConfigurationMessage: _ControlMessage {
        internal var closedGroups: Set<_CMClosedGroup> = []
        internal var openGroups: Set<String> = []
        internal var displayName: String?
        internal var profilePictureURL: String?
        internal var profileKey: Data?
        internal var contacts: Set<_CMContact> = []
        
        // MARK: NSCoding
        
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
    
    // MARK: - Config Message Closed Group

    @objc(CMClosedGroup)
    internal final class _CMClosedGroup: NSObject, NSCoding {
        internal let publicKey: String
        internal let name: String
        internal let encryptionKeyPair: SUKLegacy.KeyPair
        internal let members: Set<String>
        internal let admins: Set<String>
        internal let expirationTimer: UInt32
        
        // MARK: NSCoding

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
    
    // MARK: - Config Message Contact

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
        
        // MARK: NSCoding

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
    
    // MARK: - Unsend Request
    
    @objc(SNUnsendRequest)
    internal final class _UnsendRequest: _ControlMessage {
        internal var timestamp: UInt64?
        internal var author: String?
        
        // MARK: NSCoding
        
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
    
    // MARK: - Message Request Response
    
    @objc(SNMessageRequestResponse)
    internal final class _MessageRequestResponse: _ControlMessage {
        internal var isApproved: Bool
        
        // MARK: NSCoding

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
    
    // MARK: - Call Message
    
    /// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
    @objc(SNCallMessage)
    internal final class _CallMessage: _ControlMessage {
        internal var uuid: String
        internal var rawKind: String
        internal var sdpMLineIndexes: [UInt32]?
        internal var sdpMids: [String]?
        
        /// See https://developer.mozilla.org/en-US/docs/Glossary/SDP for more information.
        internal var sdps: [String]
        
        // MARK: - NSCoding
        
        public required init?(coder: NSCoder) {
            self.uuid = coder.decodeObject(forKey: "uuid") as! String
            self.rawKind = coder.decodeObject(forKey: "kind") as! String
            self.sdps = (coder.decodeObject(forKey: "sdps") as? [String])
                .defaulting(to: [])
            
            // These two values only exist for kind of type 'iceCandidates'
            self.sdpMLineIndexes = coder.decodeObject(forKey: "sdpMLineIndexes") as? [UInt32]
            self.sdpMids = coder.decodeObject(forKey: "sdpMids") as? [String]
            
            super.init(coder: coder)
        }

        public override func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // MARK: Non-Legacy Conversion
        
        override internal func toNonLegacy(_ instance: Message? = nil) throws -> Message {
            return try super.toNonLegacy(
                CallMessage(
                    uuid: self.uuid,
                    kind: {
                        switch self.rawKind {
                            case "preOffer": return .preOffer
                            case "offer": return .offer
                            case "answer": return .answer
                            case "provisionalAnswer": return .provisionalAnswer
                            case "iceCandidates":
                                return .iceCandidates(
                                    sdpMLineIndexes: self.sdpMLineIndexes
                                        .defaulting(to: []),
                                    sdpMids: self.sdpMids
                                        .defaulting(to: [])
                                )
                                
                            case "endCall": return .endCall
                            default: throw StorageError.migrationFailed
                        }
                    }(),
                    sdps: self.sdps
                )
            )
        }
    }
    
    // MARK: - Thread
    
    @objc(TSThread)
    public class _Thread: NSObject, NSCoding {
        public var uniqueId: String
        public var creationDate: Date
        public var shouldBeVisible: Bool
        public var isPinned: Bool
        public var mutedUntilDate: Date?
        public var messageDraft: String?
        
        // MARK: Convenience
        
        open var isClosedGroup: Bool { false }
        open var isOpenGroup: Bool { false }
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.uniqueId = coder.decodeObject(forKey: "uniqueId") as! String
            self.creationDate = coder.decodeObject(forKey: "creationDate") as! Date
            
            // Legacy version of 'shouldBeVisible'
            if let hasEverHadMessage: Bool = (coder.decodeObject(forKey: "hasEverHadMessage") as? Bool) {
                self.shouldBeVisible = hasEverHadMessage
            }
            else {
                self.shouldBeVisible = (coder.decodeObject(forKey: "shouldBeVisible") as? Bool)
                    .defaulting(to: false)
            }
            
            self.isPinned = (coder.decodeObject(forKey: "isPinned") as? Bool)
                .defaulting(to: false)
            self.mutedUntilDate = coder.decodeObject(forKey: "mutedUntilDate") as? Date
            self.messageDraft = coder.decodeObject(forKey: "messageDraft") as? String
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Contact Thread
    
    @objc(TSContactThread)
    public class _ContactThread: _Thread {
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            super.init(coder: coder)
        }
        
        // MARK: Functions
        
        internal static func threadId(from sessionId: String) -> String {
            return "\(SMKLegacy.contactThreadPrefix)\(sessionId)"
        }
        
        public static func contactSessionId(fromThreadId threadId: String) -> String {
            return String(threadId.substring(from: SMKLegacy.contactThreadPrefix.count))
        }
    }
    
    // MARK: - Group Thread
    
    @objc(TSGroupThread)
    public class _GroupThread: _Thread {
        public var groupModel: _GroupModel
        public var isOnlyNotifyingForMentions: Bool
        
        // MARK: Convenience
        
        public override var isClosedGroup: Bool { (groupModel.groupType == .closedGroup) }
        public override var isOpenGroup: Bool { (groupModel.groupType == .openGroup) }
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.groupModel = coder.decodeObject(forKey: "groupModel") as! _GroupModel
            self.isOnlyNotifyingForMentions = (coder.decodeObject(forKey: "isOnlyNotifyingForMentions") as? Bool)
                .defaulting(to: false)
            
            super.init(coder: coder)
        }
    }
    
    // MARK: - Group Model
    
    @objc(TSGroupModel)
    public class _GroupModel: NSObject, NSCoding {
        public enum _GroupType: Int {
            case closedGroup
            case openGroup
        }
        
        public var groupId: Data
        public var groupType: _GroupType
        public var groupName: String?
        public var groupMemberIds: [String]
        public var groupAdminIds: [String]

        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.groupId = coder.decodeObject(forKey: "groupId") as! Data
            self.groupType = _GroupType(rawValue: coder.decodeObject(forKey: "groupType") as! Int)!
            self.groupName = ((coder.decodeObject(forKey: "groupName") as? String) ?? "Group")
            self.groupMemberIds = coder.decodeObject(forKey: "groupMemberIds") as! [String]
            self.groupAdminIds = coder.decodeObject(forKey: "groupAdminIds") as! [String]
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Group Model
    
    @objc(SNOpenGroupV2)
    internal class _OpenGroup: NSObject, NSCoding {
        internal let server: String
        internal let room: String
        internal let id: String
        internal let name: String
        internal let publicKey: String
        internal let imageID: String?

        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.server = coder.decodeObject(forKey: "server") as! String
            self.room = coder.decodeObject(forKey: "room") as! String
            self.id = "\(self.server).\(self.room)"
            
            self.name = coder.decodeObject(forKey: "name") as! String
            self.publicKey = coder.decodeObject(forKey: "publicKey") as! String
            self.imageID = coder.decodeObject(forKey: "imageID") as? String
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Disappearing Messages Config
    
    @objc(OWSDisappearingMessagesConfiguration)
    internal class _DisappearingMessagesConfiguration: NSObject, NSCoding {
        public let uniqueId: String
        public var isEnabled: Bool
        public var durationSeconds: UInt32
        
        // MARK: NSCoder
        
        required init(coder: NSCoder) {
            self.uniqueId = coder.decodeObject(forKey: "uniqueId") as! String
            self.isEnabled = coder.decodeObject(forKey: "enabled") as! Bool
            self.durationSeconds = coder.decodeObject(forKey: "durationSeconds") as! UInt32
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Interaction
    
    @objc(TSInteraction)
    public class _DBInteraction: NSObject, NSCoding {
        public var uniqueId: String
        public var uniqueThreadId: String
        public var sortId: UInt64
        public var timestamp: UInt64
        public var receivedAtTimestamp: UInt64

        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.uniqueId = coder.decodeObject(forKey: "uniqueId") as! String
            self.uniqueThreadId = coder.decodeObject(forKey: "uniqueThreadId") as! String
            self.sortId = coder.decodeObject(forKey: "sortId") as! UInt64
            self.timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64
            self.receivedAtTimestamp = coder.decodeObject(forKey: "receivedAtTimestamp") as! UInt64
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Message
    
    @objc(TSMessage)
    public class _DBMessage: _DBInteraction {
        public var body: String?
        public var attachmentIds: [String]
        public var expiresInSeconds: UInt32
        public var expireStartedAt: UInt64
        public var expiresAt: UInt64
        public var quotedMessage: _DBQuotedMessage?
        public var linkPreview: _DBLinkPreview?
        public var openGroupServerMessageID: UInt64
        public var openGroupInvitationName: String?
        public var openGroupInvitationURL: String?
        public var serverHash: String?
        public var isDeleted: Bool
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.body = coder.decodeObject(forKey: "body") as? String
            // Note: 'attachments' was a legacy name for this key (schema version 2)
            self.attachmentIds = (coder.decodeObject(forKey: "attachments") as? [String])
                .defaulting(to: coder.decodeObject(forKey: "attachmentIds") as! [String])
            self.expiresInSeconds = coder.decodeObject(forKey: "expiresInSeconds") as! UInt32
            self.expireStartedAt = coder.decodeObject(forKey: "expireStartedAt") as! UInt64
            self.expiresAt = coder.decodeObject(forKey: "expiresAt") as! UInt64
            self.quotedMessage = coder.decodeObject(forKey: "quotedMessage") as? _DBQuotedMessage
            self.linkPreview = coder.decodeObject(forKey: "linkPreview") as? _DBLinkPreview
            self.openGroupServerMessageID = coder.decodeObject(forKey: "openGroupServerMessageID") as! UInt64
            self.openGroupInvitationName = coder.decodeObject(forKey: "openGroupInvitationName") as? String
            self.openGroupInvitationURL = coder.decodeObject(forKey: "openGroupInvitationURL") as? String
            self.serverHash = coder.decodeObject(forKey: "serverHash") as? String
            self.isDeleted = (coder.decodeObject(forKey: "isDeleted") as? Bool)
                .defaulting(to: false)
            
            super.init(coder: coder)
        }
    }
    
    // MARK: - Quoted Message
    
    @objc(TSQuotedMessage)
    public class _DBQuotedMessage: NSObject, NSCoding {
        @objc(OWSAttachmentInfo)
        public class _DBAttachmentInfo: NSObject, NSCoding {
            public var contentType: String?
            public var sourceFilename: String?
            public var attachmentId: String?
            public var thumbnailAttachmentStreamId: String?
            public var thumbnailAttachmentPointerId: String?
            
            // MARK: NSCoder
            
            public required init(coder: NSCoder) {
                self.contentType = coder.decodeObject(forKey: "contentType") as? String
                self.sourceFilename = coder.decodeObject(forKey: "sourceFilename") as? String
                self.attachmentId = coder.decodeObject(forKey: "attachmentId") as? String
                self.thumbnailAttachmentStreamId = coder.decodeObject(forKey: "thumbnailAttachmentStreamId") as? String
                self.thumbnailAttachmentPointerId = coder.decodeObject(forKey: "thumbnailAttachmentPointerId") as? String
            }
            
            public func encode(with coder: NSCoder) {
                fatalError("encode(with:) should never be called for legacy types")
            }
        }
        
        public var timestamp: UInt64
        public var authorId: String
        public var body: String?
        public var quotedAttachments: [_DBAttachmentInfo]
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64
            self.authorId = coder.decodeObject(forKey: "authorId") as! String
            self.body = coder.decodeObject(forKey: "body") as? String
            self.quotedAttachments = coder.decodeObject(forKey: "quotedAttachments") as! [_DBAttachmentInfo]
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Link Preview
    
    @objc(OWSLinkPreview)
    public class _DBLinkPreview: NSObject, NSCoding {
        public var urlString: String?
        public var title: String?
        public var imageAttachmentId: String?
        
        internal init(
            urlString: String?,
            title: String?,
            imageAttachmentId: String?
        ) {
            self.urlString = urlString
            self.title = title
            self.imageAttachmentId = imageAttachmentId
        }

        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.urlString = coder.decodeObject(forKey: "urlString") as? String
            self.title = coder.decodeObject(forKey: "title") as? String
            self.imageAttachmentId = coder.decodeObject(forKey: "imageAttachmentId") as? String
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Incoming Message
    
    @objc(TSIncomingMessage)
    public class _DBIncomingMessage: _DBMessage {
        public var authorId: String
        public var sourceDeviceId: UInt32
        public var wasRead: Bool
        public var wasReceivedByUD: Bool
        public var notificationIdentifier: String?
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.authorId = coder.decodeObject(forKey: "authorId") as! String
            self.sourceDeviceId = coder.decodeObject(forKey: "sourceDeviceId") as! UInt32
            self.wasRead = (coder.decodeObject(forKey: "read") as? Bool)  // Note: 'read' is the correct key
                .defaulting(to: false)
            self.wasReceivedByUD = (coder.decodeObject(forKey: "wasReceivedByUD") as? Bool)
                .defaulting(to: false)
            self.notificationIdentifier = coder.decodeObject(forKey: "notificationIdentifier") as? String
            
            super.init(coder: coder)
        }
    }
    
    // MARK: - Outgoing Message
    
    @objc(TSOutgoingMessage)
    public class _DBOutgoingMessage: _DBMessage {
        public var recipientStateMap: [String: _DBOutgoingMessageRecipientState]?
        public var hasSyncedTranscript: Bool
        public var customMessage: String?
        public var mostRecentFailureText: String?
        public var isVoiceMessage: Bool
        public var attachmentFilenameMap: [String: String]
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.recipientStateMap = coder.decodeObject(forKey: "recipientStateMap") as? [String: _DBOutgoingMessageRecipientState]
            self.hasSyncedTranscript = (coder.decodeObject(forKey: "hasSyncedTranscript") as? Bool)
                .defaulting(to: false)
            self.customMessage = coder.decodeObject(forKey: "customMessage") as? String
            self.mostRecentFailureText = coder.decodeObject(forKey: "mostRecentFailureText") as? String
            self.isVoiceMessage = (coder.decodeObject(forKey: "isVoiceMessage") as? Bool)
                .defaulting(to: false)
            self.attachmentFilenameMap = coder.decodeObject(forKey: "attachmentFilenameMap") as! [String: String]
            
            super.init(coder: coder)
        }
    }
    
    // MARK: - Outgoing Message Recipient State
    
    @objc(TSOutgoingMessageRecipientState)
    public class _DBOutgoingMessageRecipientState: NSObject, NSCoding {
        public enum _RecipientState: Int {
            case failed = 0
            case sending
            case skipped
            case sent
        }
        
        public var state: _RecipientState
        public var readTimestamp: Int64?
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            self.state = _RecipientState(rawValue: (coder.decodeObject(forKey: "state") as! NSNumber).intValue)!
            self.readTimestamp = coder.decodeObject(forKey: "readTimestamp") as? Int64
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    // MARK: - Info Message
    
    @objc(TSInfoMessage)
    public class _DBInfoMessage: _DBMessage {
        public enum _InfoMessageType: Int {
            case groupCreated
            case groupUpdated
            case groupCurrentUserLeft
            case disappearingMessagesUpdate
            case screenshotNotification
            case mediaSavedNotification
            case call
            case messageRequestAccepted = 99
        }
        public enum _InfoMessageCallState: Int {
            case incoming
            case outgoing
            case missed
            case permissionDenied
            case unknown
        }
        
        public var wasRead: Bool
        public var messageType: _InfoMessageType
        public var callState: _InfoMessageCallState
        public var customMessage: String?
        
        // MARK: NSCoder
        
        public required init(coder: NSCoder) {
            let parsedMessageType: _InfoMessageType = _InfoMessageType(rawValue: (coder.decodeObject(forKey: "messageType") as! NSNumber).intValue)!
            let rawCallState: Int? = (coder.decodeObject(forKey: "callState") as? NSNumber)?.intValue
            
            self.wasRead = (coder.decodeObject(forKey: "read") as? Bool)  // Note: 'read' is the correct key
                .defaulting(to: false)
            self.customMessage = coder.decodeObject(forKey: "customMessage") as? String
            
            switch (parsedMessageType, rawCallState) {
                // Note: There was a period of time where the 'messageType' value for both 'call' and
                // 'messageRequestAccepted' was the same, this code is here to handle any messages which
                // might have been mistakenly identified as 'call' messages when they should be seen as
                // 'messageRequestAccepted' messages (hard-coding a timestamp to be sure that any calls
                // after the value was changed are correctly identified as 'unknown')
                case (.call, .none):
                    guard (coder.decodeObject(forKey: "timestamp") as? UInt64 ?? 0) < 1648000000000 else {
                        fallthrough
                    }
                    
                    self.messageType = .messageRequestAccepted
                    self.callState = .unknown
                    
                default:
                    self.messageType = parsedMessageType
                    self.callState = _InfoMessageCallState(
                        rawValue: (rawCallState ?? _InfoMessageCallState.unknown.rawValue)
                    )
                    .defaulting(to: .unknown)
            }
            
            super.init(coder: coder)
        }
    }
    
    // MARK: - Disappearing Config Update Info Message
    
    public final class _DisappearingConfigurationUpdateInfoMessage: _DBInfoMessage {
        // Note: Due to how Mantle works we need to set default values for these as the 'init(dictionary:)'
        // method doesn't actually get values for them but the must be set before calling a super.init method
        // so this allows us to work around the behaviour until 'init(coder:)' method completes it's super call
        var createdByRemoteName: String?
        var configurationDurationSeconds: UInt32 = 0
        var configurationIsEnabled: Bool = false
        
        // MARK: Coding
        
        public required init(coder: NSCoder) {
            self.createdByRemoteName = coder.decodeObject(forKey: "createdByRemoteName") as? String
            self.configurationDurationSeconds = ((coder.decodeObject(forKey: "configurationDurationSeconds") as? UInt32) ?? 0)
            self.configurationIsEnabled = ((coder.decodeObject(forKey: "configurationIsEnabled") as? Bool) ?? false)
            
            super.init(coder: coder)
        }
    }
    
    // MARK: - Data Extraction Info Message
    
    @objc(SNDataExtractionNotificationInfoMessage)
    public final class _DataExtractionNotificationInfoMessage: _DBInfoMessage {
    }

    // MARK: - Attachments
    
    @objc(TSAttachment)
    internal class _Attachment: NSObject, NSCoding {
        public enum _AttachmentType: Int {
            case `default`
            case voiceMessage
        }
        
        public var serverId: UInt64
        public var encryptionKey: Data?
        public var contentType: String
        public var isDownloaded: Bool
        public var attachmentType: _AttachmentType
        public var downloadURL: String
        public var byteCount: UInt32
        public var sourceFilename: String?
        public var caption: String?
        public var albumMessageId: String?
        
        public var isImage: Bool { return MIMETypeUtil.isImage(contentType) }
        public var isVideo: Bool { return MIMETypeUtil.isVideo(contentType) }
        public var isAudio: Bool { return MIMETypeUtil.isAudio(contentType) }
        public var isAnimated: Bool { return MIMETypeUtil.isAnimated(contentType) }
        
        public var isVisualMedia: Bool { isImage || isVideo || isAnimated }
        
        // MARK: NSCoder
        
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
            self.sourceFilename = coder.decodeObject(forKey: "sourceFilename") as? String
            self.caption = coder.decodeObject(forKey: "caption") as? String
            self.albumMessageId = coder.decodeObject(forKey: "albumMessageId") as? String
        }
        
        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
    }
    
    @objc(TSAttachmentPointer)
    internal class _AttachmentPointer: _Attachment {
        public enum _State: Int {
            case enqueued
            case downloading
            case failed
        }
        
        public var state: _State
        public var mostRecentFailureLocalizedText: String?
        public var digest: Data?
        public var mediaSize: CGSize
        public var lazyRestoreFragmentId: String?
        
        // MARK: NSCoder
        
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
        public var digest: Data?
        public var isUploaded: Bool
        public var creationTimestamp: Date
        public var localRelativeFilePath: String?
        public var cachedImageWidth: NSNumber?
        public var cachedImageHeight: NSNumber?
        public var cachedAudioDurationSeconds: NSNumber?
        public var isValidImageCached: NSNumber?
        public var isValidVideoCached: NSNumber?
        
        public var isValidImage: Bool { return (isValidImageCached?.boolValue == true) }
        public var isValidVideo: Bool { return (isValidVideoCached?.boolValue == true) }
        
        public var isValidVisualMedia: Bool {
            if self.isImage && self.isValidImage { return true }
            if self.isVideo && self.isValidVideo { return true }
            if self.isAnimated && self.isValidImage { return true }
            
            return false
        }
        
        // MARK: NSCoder
        
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
    
    // MARK: - Notify Push Server Job

    @objc(NotifyPNServerJob)
    internal final class _NotifyPNServerJob: NSObject, NSCoding {
        @objc(SnodeMessage)
        internal final class _SnodeMessage: NSObject, NSCoding {
            public let recipient: String
            public let data: LosslessStringConvertible
            public let ttl: UInt64
            public let timestamp: UInt64    // Milliseconds

            // MARK: Coding
            
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

        // MARK: Coding
        
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
    
    // MARK: - Message Receive Job

    @objc(MessageReceiveJob)
    public final class _MessageReceiveJob: NSObject, NSCoding {
        public let data: Data
        public let serverHash: String?
        public let openGroupMessageServerID: UInt64?
        public let openGroupID: String?
        public let isBackgroundPoll: Bool
        public var id: String?
        public var failureCount: UInt = 0

        // MARK: Coding
        
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
    
    // MARK: - Message Send Job

    @objc(SNMessageSendJob)
    internal final class _MessageSendJob: NSObject, NSCoding {
        internal let message: _Message
        internal let destination: Message.Destination
        internal var id: String?
        internal var failureCount: UInt = 0

        // MARK: Coding
        
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
            else if _MessageSendJob.process(rawDestination, type: "openGroup") != nil {
                // We can no longer support sending messages to legacy open groups
                SNLog("[Migration Warning] Ignoring pending messageSend job for V1 OpenGroup")
                return nil
            }
            else if let destString: String = _MessageSendJob.process(rawDestination, type: "openGroupV2") {
                let components = destString
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                
                guard components.count == 2 else { return nil }
                
                let room = components[0]
                let server = components[1]
                destination = .openGroup(
                    roomToken: room,
                    server: server,
                    whisperTo: nil,
                    whisperMods: false,
                    fileIds: nil
                )
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
        
        // MARK: Convenience
        
        private static func process(_ value: String, type: String) -> String? {
            guard value.hasPrefix("\(type)(") else { return nil }
            guard value.hasSuffix(")") else { return nil }
            
            var updatedValue: String = value
            updatedValue.removeFirst("\(type)(".count)
            updatedValue.removeLast(")".count)
            
            return updatedValue
        }
    }
    
    // MARK: - Attachment Upload Job
    
    @objc(AttachmentUploadJob)
    internal final class _AttachmentUploadJob: NSObject, NSCoding {
        internal let attachmentID: String
        internal let threadID: String
        internal let message: _Message
        internal let messageSendJobID: String
        internal var id: String?
        internal var failureCount: UInt = 0
        
        // MARK: Coding
        
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
    
    // MARK: - Attachment Download Job
    
    @objc(AttachmentDownloadJob)
    public final class _AttachmentDownloadJob: NSObject, NSCoding {
        public let attachmentID: String
        public let tsMessageID: String
        public let threadID: String
        public var id: String?
        public var failureCount: UInt = 0
        public var isDeferred = false

        // MARK: Coding
        
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
}
