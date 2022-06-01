// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import Curve25519Kit
import SignalCoreKit
import SessionSnodeKit
import SessionUtilitiesKit

extension MessageReceiver {

    public static func handle(_ db: Database, message: Message, associatedWithProto proto: SNProtoContent, openGroupId: String?, isBackgroundPoll: Bool) throws {
        switch message {
            case let message as ReadReceipt: try handleReadReceipt(db, message: message)
            case let message as TypingIndicator: try handleTypingIndicator(db, message: message)
            case let message as ClosedGroupControlMessage: try handleClosedGroupControlMessage(db, message)
                
            case let message as DataExtractionNotification:
                try handleDataExtractionNotification(db, message: message)
                
            case let message as ExpirationTimerUpdate: try handleExpirationTimerUpdate(db, message: message)
            case let message as ConfigurationMessage: try handleConfigurationMessage(db, message)
            case let message as UnsendRequest: try handleUnsendRequest(db, message: message)
            case let message as MessageRequestResponse: try handleMessageRequestResponse(db, message)
                
            case let message as VisibleMessage:
                try handleVisibleMessage(db, message: message, associatedWithProto: proto, openGroupId: openGroupId, isBackgroundPoll: isBackgroundPoll)
                
            default: fatalError()
        }
        
        // When handling any non-typing indicator message we want to make sure the thread becomes
        // visible (the only other spot this flag gets set is when sending messages)
        switch message {
            case is TypingIndicator: break
                
            default:
                guard let threadInfo: (id: String, variant: SessionThread.Variant) = threadInfo(db, message: message, openGroupId: openGroupId) else {
                    return
                }
                
                _ = try SessionThread
                    .fetchOrCreate(db, id: threadInfo.id, variant: threadInfo.variant)
                    .with(shouldBeVisible: true)
                    .saved(db)
        }
    }
    
    // MARK: - Convenience
    
    private static func threadInfo(_ db: Database, message: Message, openGroupId: String?) -> (id: String, variant: SessionThread.Variant)? {
        if let openGroupId: String = openGroupId {
            // Note: We don't want to create a thread for an open group if it doesn't exist
            if (try? SessionThread.exists(db, id: openGroupId)) != true { return nil }
            
            return (openGroupId, .openGroup)
        }
        
        if let groupPublicKey: String = message.groupPublicKey {
            // Note: We don't want to create a thread for a closed group if it doesn't exist
            if (try? SessionThread.exists(db, id: groupPublicKey)) != true { return nil }
            
            return (groupPublicKey, .closedGroup)
        }
        
        // Extract the 'syncTarget' value if there is one
        let maybeSyncTarget: String?
        
        switch message {
            case let message as VisibleMessage: maybeSyncTarget = message.syncTarget
            case let message as ExpirationTimerUpdate: maybeSyncTarget = message.syncTarget
            default: maybeSyncTarget = nil
        }
        
        // Note: We don't want to create a thread for a closed group if it doesn't exist
        guard let contactId: String = (maybeSyncTarget ?? message.sender) else { return nil }
        
        return (contactId, .contact)
    }
    
    // MARK: - Read Receipts
    
    private static func handleReadReceipt(_ db: Database, message: ReadReceipt) throws {
        guard let sender: String = message.sender else { return }
        guard let timestampMsValues: [Double] = message.timestamps?.map({ Double($0) }) else { return }
        guard let readTimestampMs: Double = message.receivedTimestamp.map({ Double($0) }) else { return }
        
        try Interaction.markAsRead(
            db,
            recipientId: sender,
            timestampMsValues: timestampMsValues,
            readTimestampMs: readTimestampMs
        )
    }

    // MARK: - Typing Indicators
    
    private static func handleTypingIndicator(_ db: Database, message: TypingIndicator) throws {
        guard
            let senderPublicKey: String = message.sender,
            let thread: SessionThread = try SessionThread.fetchOne(db, id: senderPublicKey)
        else { return }
        
        switch message.kind {
            case .started:
                TypingIndicators.didStartTyping(
                    db,
                    threadId: thread.id,
                    threadVariant: thread.variant,
                    threadIsMessageRequest: thread.isMessageRequest(db),
                    direction: .incoming,
                    timestampMs: message.sentTimestamp.map { Int64($0) }
                )
                
            case .stopped:
                TypingIndicators.didStopTyping(db, threadId: thread.id, direction: .incoming)
            
            default:
                SNLog("Unknown TypingIndicator Kind ignored")
                return
        }
    }
    
    // MARK: - Data Extraction Notification
    
    private static func handleDataExtractionNotification(_ db: Database, message: DataExtractionNotification) throws {
        guard
            let sender: String = message.sender,
            let messageKind: DataExtractionNotification.Kind = message.kind,
            let thread: SessionThread = try? SessionThread.fetchOne(db, id: sender),
            thread.variant == .contact
        else { return }
        
        _ = try Interaction(
            serverHash: message.serverHash,
            threadId: thread.id,
            authorId: sender,
            variant: {
                switch messageKind {
                    case .screenshot: return .infoScreenshotNotification
                    case .mediaSaved: return .infoMediaSavedNotification
                }
            }()
        ).inserted(db)
    }
    
    // MARK: - Expiration Timers

    private static func handleExpirationTimerUpdate(_ db: Database, message: ExpirationTimerUpdate) throws {
        // Get the target thread
        guard
            let targetId: String = threadInfo(db, message: message, openGroupId: nil)?.id,
            let sender: String = message.sender,
            let thread: SessionThread = try? SessionThread.fetchOne(db, id: targetId)
        else { return }
        
        // Update the configuration
        //
        // Note: Messages which had been sent during the previous configuration will still
        // use it's settings (so if you enable, send a message and then disable disappearing
        // message then the message you had sent will still disappear)
        let config: DisappearingMessagesConfiguration = try thread.disappearingMessagesConfiguration
            .fetchOne(db)
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(thread.id))
            .with(
                // If there is no duration then we should disable the expiration timer
                isEnabled: ((message.duration ?? 0) > 0),
                durationSeconds: (
                    message.duration.map { TimeInterval($0) } ??
                    DisappearingMessagesConfiguration.defaultDuration
                )
            )
        
        // Add an info message for the user
        _ = try Interaction(
            serverHash: nil, // Intentionally null so sync messages are seen as duplicates
            threadId: thread.id,
            authorId: sender,
            variant: .infoDisappearingMessagesUpdate,
            body: config.messageInfoString(
                with: (sender != getUserHexEncodedPublicKey(db) ?
                    Profile.displayName(db, id: sender) :
                    nil
                )
            ),
            timestampMs: Int64(message.sentTimestamp ?? 0)   // Default to `0` if not set
        ).inserted(db)
        
        // Finally save the changes to the DisappearingMessagesConfiguration (If it's a duplicate
        // then the interaction unique constraint will prevent the code from getting here)
        try config.save(db)
    }
    
    // MARK: - Configuration Messages
    
    private static func handleConfigurationMessage(_ db: Database, _ message: ConfigurationMessage) throws {
        let userPublicKey = getUserHexEncodedPublicKey(db)
        
        guard message.sender == userPublicKey else { return }
        
        SNLog("Configuration message received.")
        
        // Note: `message.sentTimestamp` is in ms (convert to TimeInterval before converting to
        // seconds to maintain the accuracy)
        let isInitialSync: Bool = (!UserDefaults.standard[.hasSyncedInitialConfiguration])
        let messageSentTimestamp: TimeInterval = TimeInterval((message.sentTimestamp ?? 0) / 1000)
        let lastConfigTimestamp: TimeInterval = UserDefaults.standard[.lastConfigurationSync]
            .defaulting(to: Date(timeIntervalSince1970: 0))
            .timeIntervalSince1970
        
        // Profile
        try updateProfileIfNeeded(
            db,
            publicKey: userPublicKey,
            name: message.displayName,
            profilePictureUrl: message.profilePictureUrl,
            profileKey: OWSAES256Key(data: message.profileKey),
            sentTimestamp: messageSentTimestamp
        )
        
        if isInitialSync || messageSentTimestamp > lastConfigTimestamp {
            if isInitialSync {
                UserDefaults.standard[.hasSyncedInitialConfiguration] = true
                NotificationCenter.default.post(name: .initialConfigurationMessageReceived, object: nil)
            }
            
            UserDefaults.standard[.lastConfigurationSync] = Date(timeIntervalSince1970: messageSentTimestamp)
            
            // Contacts
            try message.contacts.forEach { contactInfo in
                guard let sessionId: String = contactInfo.publicKey else { return }
                
                let contact: Contact = Contact.fetchOrCreate(db, id: sessionId)
                let profile: Profile = Profile.fetchOrCreate(db, id: sessionId)
                
                try profile
                    .with(
                        name: contactInfo.displayName,
                        profilePictureUrl: .updateIf(contactInfo.profilePictureUrl),
                        profileEncryptionKey: .updateIf(
                            contactInfo.profileKey.map { OWSAES256Key(data: $0) }
                        )
                    )
                    .save(db)
                
                /// We only update these values if the proto actually has values for them (this is to prevent an
                /// edge case where an old client could override the values with default values since they aren't included)
                ///
                /// **Note:** Since message requests have no reverse, we should only handle setting `isApproved`
                /// and `didApproveMe` to `true`. This may prevent some weird edge cases where a config message
                /// swapping `isApproved` and `didApproveMe` to `false`
                try contact
                    .with(
                        isApproved: (contactInfo.hasIsApproved && contactInfo.isApproved ?
                            true :
                            .existing
                        ),
                        isBlocked: (contactInfo.hasIsBlocked ?
                            .update(contactInfo.isBlocked) :
                            .existing
                        ),
                        didApproveMe: (contactInfo.hasDidApproveMe && contactInfo.didApproveMe ?
                            true :
                            .existing
                        )
                    )
                    .save(db)
                
                // If the contact is blocked
                if contactInfo.hasIsBlocked && contactInfo.isBlocked {
                    // If this message changed them to the blocked state and there is an existing thread
                    // associated with them that is a message request thread then delete it (assume
                    // that the current user had deleted that message request)
                    if
                        contactInfo.isBlocked != contact.isBlocked,
                        let thread: SessionThread = try? SessionThread.fetchOne(db, id: sessionId),
                        thread.isMessageRequest(db)
                    {
                        _ = try thread.delete(db)
                    }
                }
            }
            
            // Closed groups
            //
            // Note: Only want to add these for initial sync to avoid re-adding closed groups the user
            // intentionally left (any closed groups joined since the first processed sync message should
            // get added via the 'handleNewClosedGroup' method anyway as they will have come through in the
            // past two weeks)
            if isInitialSync {
                let existingClosedGroupsIds: [String] = (try? SessionThread
                    .filter(SessionThread.Columns.variant == SessionThread.Variant.closedGroup)
                    .fetchAll(db))
                    .defaulting(to: [])
                    .map { $0.id }
                
                try message.closedGroups.forEach { closedGroup in
                    guard !existingClosedGroupsIds.contains(closedGroup.publicKey) else { return }
                    
                    let keyPair: Box.KeyPair = Box.KeyPair(
                        publicKey: closedGroup.encryptionKeyPublicKey.bytes,
                        secretKey: closedGroup.encryptionKeySecretKey.bytes
                    )
                    
                    try handleNewClosedGroup(
                        db,
                        groupPublicKey: closedGroup.publicKey,
                        name: closedGroup.name,
                        encryptionKeyPair: keyPair,
                        members: [String](closedGroup.members),
                        admins: [String](closedGroup.admins),
                        expirationTimer: closedGroup.expirationTimer,
                        messageSentTimestamp: message.sentTimestamp!
                    )
                }
            }
            
            // Open groups
            for openGroupURL in message.openGroups {
                if let (room, server, publicKey) = OpenGroupManagerV2.parseV2OpenGroup(from: openGroupURL) {
                    OpenGroupManagerV2.shared
                        .add(db, room: room, server: server, publicKey: publicKey)
                        .retainUntilComplete()
                }
            }
        }
    }
    
    // MARK: - Unsend Requests
    
    public static func handleUnsendRequest(_ db: Database, message: UnsendRequest) throws {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        guard message.sender == message.author || userPublicKey == message.sender else { return }
        guard let author: String = message.author, let timestampMs: UInt64 = message.timestamp else { return }
        
        let maybeInteraction: Interaction? = try Interaction
            .filter(Interaction.Columns.timestampMs == Int64(timestampMs))
            .filter(Interaction.Columns.authorId == author)
            .fetchOne(db)
        
        guard
            let interactionId: Int64 = maybeInteraction?.id,
            let interaction: Interaction = maybeInteraction
        else { return }
        
        // Mark incoming messages as read and remove any of their notifications
        if interaction.variant == .standardIncoming {
            try Interaction.markAsRead(
                db,
                interactionId: interactionId,
                threadId: interaction.threadId,
                includingOlder: false,
                trySendReadReceipt: false
            )
            
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: interaction.notificationIdentifiers)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: interaction.notificationIdentifiers)
        }
        
        if author == message.sender, let serverHash: String = interaction.serverHash {
            SnodeAPI.deleteMessage(publicKey: author, serverHashes: [serverHash]).retainUntilComplete()
        }
         
        switch (interaction.variant, (author == message.sender)) {
            case (.standardOutgoing, _), (_, false):
                _ = try interaction.delete(db)
                
            case (_, true):
                _ = try interaction
                    .markingAsDeleted()
                    .saved(db)
                
                _ = try interaction.attachments
                    .deleteAll(db)
        }
    }
    
    // MARK: - Visible Messages

    @discardableResult public static func handleVisibleMessage(
        _ db: Database,
        message: VisibleMessage,
        associatedWithProto proto: SNProtoContent,
        openGroupId: String?,
        isBackgroundPoll: Bool
    ) throws -> Int64 {
        guard let sender: String = message.sender, let dataMessage = proto.dataMessage else {
            throw MessageReceiverError.invalidMessage
        }
        
        // Note: `message.sentTimestamp` is in ms (convert to TimeInterval before converting to
        // seconds to maintain the accuracy)
        let messageSentTimestamp: TimeInterval = (TimeInterval(message.sentTimestamp ?? 0) / 1000)
        let isMainAppActive: Bool = (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false)
        
        // Update profile if needed (want to do this regardless of whether the message exists or
        // not to ensure the profile info gets sync between a users devices at every chance)
        if let profile = message.profile {
            var contactProfileKey: OWSAES256Key? = nil
            if let profileKey = profile.profileKey { contactProfileKey = OWSAES256Key(data: profileKey) }
            
            try updateProfileIfNeeded(
                db,
                publicKey: sender,
                name: profile.displayName,
                profilePictureUrl: profile.profilePictureUrl,
                profileKey: contactProfileKey,
                sentTimestamp: messageSentTimestamp
            )
        }
        
        // Get or create thread
        guard let threadInfo: (id: String, variant: SessionThread.Variant) = threadInfo(db, message: message, openGroupId: openGroupId) else {
            throw MessageReceiverError.noThread
        }

        // Store the message variant so we can run variant-specific behaviours
        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
        let thread: SessionThread = try SessionThread
            .fetchOrCreate(db, id: threadInfo.id, variant: threadInfo.variant)
        let variant: Interaction.Variant = (sender == currentUserPublicKey ?
            .standardOutgoing :
            .standardIncoming
        )
        
        // Retrieve the disappearing messages config to set the 'expiresInSeconds' value
        // accoring to the config
        let disappearingMessagesConfiguration: DisappearingMessagesConfiguration = (try? thread.disappearingMessagesConfiguration.fetchOne(db))
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(thread.id))
        
        // Try to insert the interaction
        //
        // Note: There are now a number of unique constraints on the database which
        // prevent the ability to insert duplicate interactions at a database level
        // so we don't need to check for the existance of a message beforehand anymore
        let interaction: Interaction
        
        do {
            interaction = try Interaction(
                serverHash: message.serverHash, // Keep track of server hash
                threadId: thread.id,
                authorId: sender,
                variant: variant,
                body: message.text,
                timestampMs: Int64(messageSentTimestamp * 1000),
                wasRead: (variant == .standardOutgoing), // Auto-mark sent messages as read
                hasMention: (
                    message.text?.contains("@\(currentUserPublicKey)") == true ||
                    dataMessage.quote?.author == currentUserPublicKey
                ),
                // Note: Ensure we don't ever expire open group messages
                expiresInSeconds: (disappearingMessagesConfiguration.isEnabled && message.openGroupServerMessageId == nil ?
                    disappearingMessagesConfiguration.durationSeconds :
                    nil
                ),
                expiresStartedAtMs: nil,
                // OpenGroupInvitations are stored as LinkPreview's in the database
                linkPreviewUrl: (message.linkPreview?.url ?? message.openGroupInvitation?.url),
                // Keep track of the open group server message ID ↔ message ID relationship
                openGroupServerMessageId: message.openGroupServerMessageId.map { Int64($0) },
                openGroupWhisperMods: false,
                openGroupWhisperTo: nil
            ).inserted(db)
        }
        catch {
            switch error {
                case DatabaseError.SQLITE_CONSTRAINT_UNIQUE:
                    guard
                        variant == .standardOutgoing,
                        let existingInteractionId: Int64 = try? thread.interactions
                            .select(.id)
                            .filter(Interaction.Columns.timestampMs == (messageSentTimestamp * 1000))
                            .filter(Interaction.Columns.variant == variant)
                            .filter(Interaction.Columns.authorId == sender)
                            .asRequest(of: Int64.self)
                            .fetchOne(db)
                    else { break }
                    
                    // If we receive an outgoing message that already exists in the database
                    // then we still need up update the recipient and read states for the
                    // message (even if we don't need to do anything else)
                    try updateRecipientAndReadStates(
                        db,
                        thread: thread,
                        interactionId: existingInteractionId,
                        variant: variant,
                        syncTarget: message.syncTarget
                    )
                    
                default: break
            }
            
            throw error
        }
        
        guard let interactionId: Int64 = interaction.id else { throw StorageError.failedToSave }
        
        // Update and recipient and read states as needed
        try updateRecipientAndReadStates(
            db,
            thread: thread,
            interactionId: interactionId,
            variant: variant,
            syncTarget: message.syncTarget
        )
            
        // Parse & persist attachments
        let attachments: [Attachment] = try dataMessage.attachments
            .compactMap { proto -> Attachment? in
                let attachment: Attachment = Attachment(proto: proto)
                
                // Attachments on received messages must have a 'downloadUrl' otherwise
                // they are invalid and we can ignore them
                return (attachment.downloadUrl != nil ? attachment : nil)
            }
            .enumerated()
            .map { index, attachment in
                let savedAttachment: Attachment = try attachment.saved(db)
                
                // Link the attachment to the interaction and add to the id lookup
                try InteractionAttachment(
                    albumIndex: index,
                    interactionId: interactionId,
                    attachmentId: savedAttachment.id
                ).insert(db)
                
                return savedAttachment
            }
        
        message.attachmentIds = attachments.map { $0.id }
        
        // Persist quote if needed
        let quote: Quote? = try? Quote(
            db,
            proto: dataMessage,
            interactionId: interactionId,
            thread: thread
        )?.inserted(db)
        
        // Parse link preview if needed
        let linkPreview: LinkPreview? = try? LinkPreview(
            db,
            proto: dataMessage,
            body: message.text,
            sentTimestampMs: (messageSentTimestamp * 1000)
        )?.saved(db)
        
        // Open group invitations are stored as LinkPreview values so create one if needed
        if
            let openGroupInvitationUrl: String = message.openGroupInvitation?.url,
            let openGroupInvitationName: String = message.openGroupInvitation?.name
        {
            try LinkPreview(
                url: openGroupInvitationUrl,
                timestamp: LinkPreview.timestampFor(sentTimestampMs: (messageSentTimestamp * 1000)),
                variant: .openGroupInvitation,
                title: openGroupInvitationName
            ).save(db)
        }
        
        // Start attachment downloads if needed (ie. trusted contact or group thread)
        let isContactTrusted: Bool = ((try? Contact.fetchOne(db, id: sender))?.isTrusted ?? false)

        if isContactTrusted || thread.variant != .contact {
            attachments
                .map { $0.id }
                .appending(quote?.attachmentId)
                .appending(linkPreview?.attachmentId)
                .forEach { attachmentId in
                    JobRunner.add(
                        db,
                        job: Job(
                            variant: .attachmentDownload,
                            threadId: thread.id,
                            interactionId: interactionId,
                            details: AttachmentDownloadJob.Details(
                                attachmentId: attachmentId
                            )
                        ),
                        canStartJob: isMainAppActive
                    )
                }
        }
        
        // Cancel any typing indicators if needed
        if isMainAppActive {
            TypingIndicators.didStopTyping(db, threadId: thread.id, direction: .incoming)
        }
        
        // Update the contact's approval status of the current user if needed (if we are getting messages from
        // them outside of a group then we can assume they have approved the current user)
        //
        // Note: This is to resolve a rare edge-case where a conversation was started with a user on an old
        // version of the app and their message request approval state was set via a migration rather than
        // by using the approval process
        if thread.variant == .contact {
            try updateContactApprovalStatusIfNeeded(
                db,
                senderSessionId: sender,
                threadId: thread.id,
                forceConfigSync: false
            )
        }
        
        // Notify the user if needed
        guard variant == .standardIncoming else { return interactionId }
        
        // Use the same identifier for notifications when in backgroud polling to prevent spam
        SSKEnvironment.shared.notificationsManager.wrappedValue?
            .notifyUser(
                db,
                for: interaction,
                in: thread,
                isBackgroundPoll: isBackgroundPoll
            )
        
        return interactionId
    }
    
    private static func updateRecipientAndReadStates(
        _ db: Database,
        thread: SessionThread,
        interactionId: Int64,
        variant: Interaction.Variant,
        syncTarget: String?
    ) throws {
        guard variant == .standardOutgoing else { return }
        
        if let syncTarget: String = syncTarget {
            try RecipientState(
                interactionId: interactionId,
                recipientId: syncTarget,
                state: .sent
            ).save(db)
        }
        else if thread.variant == .closedGroup {
            try GroupMember
                .filter(GroupMember.Columns.groupId == thread.id)
                .fetchAll(db)
                .forEach { member in
                    try RecipientState(
                        interactionId: interactionId,
                        recipientId: member.profileId,
                        state: .sent
                    ).save(db)
                }
        }
    
        // For outgoing messages mark all older interactions as read (the user should have seen
        // them if they send a message - also avoids a situation where the user has "phantom"
        // unread messages that they need to scroll back to before they become marked as read)
        try Interaction.markAsRead(
            db,
            interactionId: interactionId,
            threadId: thread.id,
            includingOlder: true,
            trySendReadReceipt: true
        )
    }
    
    // MARK: - Profile Updating
    
    private static func updateProfileIfNeeded(
        _ db: Database,
        publicKey: String,
        name: String?,
        profilePictureUrl: String?,
        profileKey: OWSAES256Key?,
        sentTimestamp: TimeInterval
    ) throws {
        let isCurrentUser = (publicKey == getUserHexEncodedPublicKey(db))
        var profile: Profile = Profile.fetchOrCreate(id: publicKey)
        
        // Name
        if let name = name, name != profile.name {
            let shouldUpdate: Bool
            if isCurrentUser {
                shouldUpdate = given(UserDefaults.standard[.lastDisplayNameUpdate]) {
                    sentTimestamp > $0.timeIntervalSince1970
                }
                .defaulting(to: true)
            }
            else {
                shouldUpdate = true
            }
            
            if shouldUpdate {
                if isCurrentUser {
                    UserDefaults.standard[.lastDisplayNameUpdate] = Date(timeIntervalSince1970: sentTimestamp)
                }
                
                profile = profile.with(name: name)
            }
        }
        
        // Profile picture & profile key
        if
            let profileKey: OWSAES256Key = profileKey,
            let profilePictureUrl: String = profilePictureUrl,
            profileKey.keyData.count == kAES256_KeyByteLength,
            profileKey != profile.profileEncryptionKey
        {
            let shouldUpdate: Bool
            if isCurrentUser {
                shouldUpdate = given(UserDefaults.standard[.lastProfilePictureUpdate]) {
                    sentTimestamp > $0.timeIntervalSince1970
                }
                .defaulting(to: true)
            }
            else {
                shouldUpdate = true
            }
            
            if shouldUpdate {
                if isCurrentUser {
                    UserDefaults.standard[.lastProfilePictureUpdate] = Date(timeIntervalSince1970: sentTimestamp)
                }
                
                profile = profile.with(
                    profilePictureUrl: .update(profilePictureUrl),
                    profileEncryptionKey: .update(profileKey)
                )
            }
        }
        
        // Persist changes
        try profile.save(db)
        
        // Download the profile picture if needed
        db.afterNextTransactionCommit { _ in
            ProfileManager.downloadAvatar(for: profile)
        }
    }
    
    // MARK: - Closed Groups
    
    public static func handleClosedGroupControlMessage(_ db: Database, _ message: ClosedGroupControlMessage) throws {
        switch message.kind! {
            case .new: try handleNewClosedGroup(db, message: message)
            case .encryptionKeyPair: try handleClosedGroupEncryptionKeyPair(db, message: message)
            case .nameChange: try handleClosedGroupNameChanged(db, message: message)
            case .membersAdded: try handleClosedGroupMembersAdded(db, message: message)
            case .membersRemoved: try handleClosedGroupMembersRemoved(db, message: message)
            case .memberLeft: try handleClosedGroupMemberLeft(db, message: message)
            case .encryptionKeyPairRequest:
                handleClosedGroupEncryptionKeyPairRequest(db, message: message) // Currently not used
        }
    }
    
    private static func handleNewClosedGroup(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .new(publicKeyAsData, name, encryptionKeyPair, membersAsData, adminsAsData, expirationTimer) = message.kind else {
            return
        }
        guard let sentTimestamp: UInt64 = message.sentTimestamp else { return }
        
        try handleNewClosedGroup(
            db,
            groupPublicKey: publicKeyAsData.toHexString(),
            name: name,
            encryptionKeyPair: encryptionKeyPair,
            members: membersAsData.map { $0.toHexString() },
            admins: adminsAsData.map { $0.toHexString() },
            expirationTimer: expirationTimer,
            messageSentTimestamp: sentTimestamp
        )
    }

    private static func handleNewClosedGroup(
        _ db: Database,
        groupPublicKey: String,
        name: String,
        encryptionKeyPair: Box.KeyPair,
        members: [String],
        admins: [String],
        expirationTimer: UInt32,
        messageSentTimestamp: UInt64
    ) throws {
        // With new closed groups we only want to create them if the admin creating the closed group is an
        // approved contact (to prevent spam via closed groups getting around message requests if users are
        // on old or modified clients)
        var hasApprovedAdmin: Bool = false
        
        for adminId in admins {
            if let contact: Contact = try? Contact.fetchOne(db, id: adminId), contact.isApproved {
                hasApprovedAdmin = true
                break
            }
        }
        
        guard hasApprovedAdmin else { return }
        
        // Create the group
        let groupAlreadyExisted: Bool = ((try? SessionThread.exists(db, id: groupPublicKey)) ?? false)
        let thread: SessionThread = try SessionThread
            .fetchOrCreate(db, id: groupPublicKey, variant: .closedGroup)
            .with(shouldBeVisible: true)
            .saved(db)
        let closedGroup: ClosedGroup = try ClosedGroup(
            threadId: groupPublicKey,
            name: name,
            formationTimestamp: (TimeInterval(messageSentTimestamp) / 1000)
        ).saved(db)
        
        // Clear the zombie list if the group wasn't active (ie. had no keys)
        if ((try? closedGroup.keyPairs.fetchCount(db)) ?? 0) == 0 {
            try closedGroup.zombies.deleteAll(db)
        }
        
        // Notify the user
        if !groupAlreadyExisted {
            // Create the GroupMember records
            try members.forEach { memberId in
                try GroupMember(
                    groupId: groupPublicKey,
                    profileId: memberId,
                    role: .standard
                ).save(db)
            }
            
            try admins.forEach { adminId in
                try GroupMember(
                    groupId: groupPublicKey,
                    profileId: adminId,
                    role: .admin
                ).save(db)
            }
            
            // Note: We don't provide a `serverHash` in this case as we want to allow duplicates
            // to avoid the following situation:
            // • The app performed a background poll or received a push notification
            // • This method was invoked and the received message timestamps table was updated
            // • Processing wasn't finished
            // • The user doesn't see the new closed group
            _ = try Interaction(
                threadId: thread.id,
                authorId: getUserHexEncodedPublicKey(db),
                variant: .infoClosedGroupCreated,
                timestampMs: Int64(messageSentTimestamp)
            ).inserted(db)
        }
        
        // Update the DisappearingMessages config
        try thread.disappearingMessagesConfiguration
            .fetchOne(db)
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(thread.id))
            .with(
                isEnabled: (expirationTimer > 0),
                durationSeconds: TimeInterval(expirationTimer > 0 ?
                    expirationTimer :
                    (24 * 60 * 60)
                )
            )
            .save(db)
        
        // Store the key pair
        try ClosedGroupKeyPair(
            threadId: groupPublicKey,
            publicKey: Data(encryptionKeyPair.publicKey),
            secretKey: Data(encryptionKeyPair.secretKey),
            receivedTimestamp: Date().timeIntervalSince1970
        ).insert(db)
        
        // Start polling
        ClosedGroupPoller.shared.startPolling(for: groupPublicKey)
        
        // Notify the PN server
        let _ = PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey())
    }

    /// Extracts and adds the new encryption key pair to our list of key pairs if there is one for our public key, AND the message was
    /// sent by the group admin.
    private static func handleClosedGroupEncryptionKeyPair(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard
            case let .encryptionKeyPair(explicitGroupPublicKey, wrappers) = message.kind,
            let groupPublicKey: String = (explicitGroupPublicKey?.toHexString() ?? message.groupPublicKey)
        else { return }
        guard let userKeyPair: Box.KeyPair = Identity.fetchUserKeyPair(db) else {
            return SNLog("Couldn't find user X25519 key pair.")
        }
        guard let thread: SessionThread = try? SessionThread.fetchOne(db, id: groupPublicKey) else {
            return SNLog("Ignoring closed group encryption key pair for nonexistent group.")
        }
        guard let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db) else { return }
        guard let groupAdmins: [GroupMember] = try? closedGroup.admins.fetchAll(db) else { return }
        guard let sender: String = message.sender, groupAdmins.contains(where: { $0.profileId == sender }) else {
            return SNLog("Ignoring closed group encryption key pair from non-admin.")
        }
        // Find our wrapper and decrypt it if possible
        let userPublicKey: String = userKeyPair.publicKey.toHexString()
        
        guard
            let wrapper = wrappers.first(where: { $0.publicKey == userPublicKey }),
            let encryptedKeyPair = wrapper.encryptedKeyPair
        else { return }
        
        let plaintext: Data
        do {
            plaintext = try MessageReceiver.decryptWithSessionProtocol(
                ciphertext: encryptedKeyPair,
                using: userKeyPair
            ).plaintext
        }
        catch {
            return SNLog("Couldn't decrypt closed group encryption key pair.")
        }
        
        // Parse it
        let proto: SNProtoKeyPair
        do {
            proto = try SNProtoKeyPair.parseData(plaintext)
        }
        catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        
        do {
            try ClosedGroupKeyPair(
                threadId: groupPublicKey,
                publicKey: proto.publicKey.removing05PrefixIfNeeded(),
                secretKey: proto.privateKey,
                receivedTimestamp: Date().timeIntervalSince1970
            ).insert(db)
        }
        catch {
            return SNLog("Ignoring duplicate closed group encryption key pair.")
        }
        
        SNLog("Received a new closed group encryption key pair.")
    }
    
    private static func handleClosedGroupNameChanged(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .nameChange(name) = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            try closedGroup
                .with(name: name)
                .save(db)

            // Notify the user if needed
            guard name != closedGroup.name else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .nameChange(name: name)
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
    
    private static func handleClosedGroupMembersAdded(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .membersAdded(membersAsData) = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            guard let groupMembers: [GroupMember] = try? closedGroup.members.fetchAll(db) else { return }
            guard let groupAdmins: [GroupMember] = try? closedGroup.admins.fetchAll(db) else { return }
            
            // Update the group
            let addedMembers: [String] = membersAsData.map { $0.toHexString() }
            let currentMemberIds: Set<String> = groupMembers.map { $0.profileId }.asSet()
            let members: Set<String> = currentMemberIds.union(addedMembers)
        
            // Create records for any new members
            try addedMembers
                .filter { !currentMemberIds.contains($0) }
                .forEach { memberId in
                    try GroupMember(
                        groupId: id,
                        profileId: memberId,
                        role: .standard
                    ).insert(db)
                }
            
            // Send the latest encryption key pair to the added members if the current user is
            // the admin of the group
            //
            // This fixes a race condition where:
            // • A member removes another member.
            // • A member adds someone to the group and sends them the latest group key pair.
            // • The admin is offline during all of this.
            // • When the admin comes back online they see the member removed message and generate +
            //   distribute a new key pair, but they don't know about the added member yet.
            // • Now they see the member added message.
            //
            // Without the code below, the added member(s) would never get the key pair that was
            // generated by the admin when they saw the member removed message.
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            
            if groupAdmins.contains(where: { $0.profileId == userPublicKey }) {
                addedMembers.forEach { memberId in
                    MessageSender.sendLatestEncryptionKeyPair(db, to: memberId, for: id)
                }
            }
            
            // Remove any 'zombie' versions of the added members (in case they were re-added)
            _ = try closedGroup
                .zombies
                .filter(addedMembers.contains(GroupMember.Columns.profileId))
                .deleteAll(db)
            
            // Notify the user if needed
            guard members != Set(groupMembers.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .membersAdded(
                        members: addedMembers
                            .asSet()
                            .subtracting(groupMembers.map { $0.profileId })
                            .map { Data(hex: $0) }
                    )
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
 
    /// Removes the given members from the group IF
    /// • it wasn't the admin that was removed (that should happen through a `MEMBER_LEFT` message).
    /// • the admin sent the message (only the admin can truly remove members).
    /// If we're among the users that were removed, delete all encryption key pairs and the group public key, unsubscribe
    /// from push notifications for this closed group, and remove the given members from the zombie list for this group.
    private static func handleClosedGroupMembersRemoved(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case let .membersRemoved(membersAsData) = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            // Check that the admin wasn't removed
            guard let groupMembers: [GroupMember] = try? closedGroup.members.fetchAll(db) else { return }
            guard let groupAdmins: [GroupMember] = try? closedGroup.admins.fetchAll(db) else { return }
            
            let removedMembers = membersAsData.map { $0.toHexString() }
            let members = Set(groupMembers.map { $0.profileId }).subtracting(removedMembers)
            
            guard let firstAdminId: String = groupAdmins.first?.profileId, members.contains(firstAdminId) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            // Check that the message was sent by the group admin
            guard groupAdmins.contains(where: { $0.profileId == sender }) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            
            // If the current user was removed:
            // • Stop polling for the group
            // • Remove the key pairs associated with the group
            // • Notify the PN server
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let wasCurrentUserRemoved: Bool = !members.contains(userPublicKey)
            
            if wasCurrentUserRemoved {
                ClosedGroupPoller.shared.stopPolling(for: id)
                
                try closedGroup
                    .allMembers
                    .deleteAll(db)
                
                _ = try closedGroup
                    .keyPairs
                    .deleteAll(db)
                
                let _ = PushNotificationAPI.performOperation(
                    .unsubscribe,
                    for: id,
                    publicKey: userPublicKey
                )
            }
            else {
                // Remove the member from the group and it's zombies
                try closedGroup.members
                    .filter(removedMembers.contains(GroupMember.Columns.profileId))
                    .deleteAll(db)
                try closedGroup.zombies
                    .filter(removedMembers.contains(GroupMember.Columns.profileId))
                    .deleteAll(db)
            }
            
            // Notify the user if needed
            guard members != Set(groupMembers.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: (wasCurrentUserRemoved ? .infoClosedGroupCurrentUserLeft : .infoClosedGroupUpdated),
                body: ClosedGroupControlMessage.Kind
                    .membersRemoved(
                        members: removedMembers
                            .asSet()
                            .subtracting(groupMembers.map { $0.profileId })
                            .map { Data(hex: $0) }
                    )
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
    
    /// If a regular member left:
    /// • Mark them as a zombie (to be removed by the admin later).
    /// If the admin left:
    /// • Unsubscribe from PNs, delete the group public key, etc. as the group will be disbanded.
    private static func handleClosedGroupMemberLeft(_ db: Database, message: ClosedGroupControlMessage) throws {
        guard case .memberLeft = message.kind else { return }
        
        try performIfValid(db, message: message) { id, sender, thread, closedGroup in
            guard let allGroupMembers: [GroupMember] = try? closedGroup.allMembers.fetchAll(db) else {
                return
            }
            
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let didAdminLeave: Bool = allGroupMembers.contains(where: { member in
                member.role == .admin && member.profileId == sender
            })
            let members: [GroupMember] = allGroupMembers.filter { $0.role == .standard }
            let membersToRemove: [GroupMember] = members
                .filter { member in
                    didAdminLeave || // If the admin leaves the group is disbanded
                    member.profileId == sender
                }
            let updatedMemberIds: Set<String> = members
                .map { $0.profileId }
                .asSet()
                .subtracting(membersToRemove.map { $0.profileId })
            
            
            if didAdminLeave || sender == userPublicKey {
                // Remove the group from the database and unsubscribe from PNs
                ClosedGroupPoller.shared.stopPolling(for: id)
                
                try closedGroup
                    .allMembers
                    .deleteAll(db)
                
                _ = try closedGroup
                    .keyPairs
                    .deleteAll(db)
                
                let _ = PushNotificationAPI.performOperation(
                    .unsubscribe,
                    for: id,
                    publicKey: userPublicKey
                )
            }
            else {
                // Delete all old user roles and re-add them as a zombie
                try closedGroup
                    .allMembers
                    .filter(GroupMember.Columns.profileId == sender)
                    .deleteAll(db)
                
                try GroupMember(
                    groupId: id,
                    profileId: sender,
                    role: .zombie
                ).insert(db)
            }
            
            // Notify the user if needed
            guard updatedMemberIds != Set(members.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .memberLeft
                    .infoMessage(db, sender: sender),
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
    }
    
    private static func handleClosedGroupEncryptionKeyPairRequest(_ db: Database, message: ClosedGroupControlMessage) {
        /*
        guard case .encryptionKeyPairRequest = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, _, group in
            let publicKey = message.sender!
            // Guard against self-sends
            guard publicKey != getUserHexEncodedPublicKey() else {
                return SNLog("Ignoring invalid closed group update.")
            }
            MessageSender.sendLatestEncryptionKeyPair(to: publicKey, for: groupPublicKey, using: transaction)
        }
         */
    }
    
    private static func performIfValid(
        _ db: Database,
        message: ClosedGroupControlMessage,
        _ update: (String, String, SessionThread, ClosedGroup
    ) throws -> Void) throws {
        guard let groupPublicKey: String = message.groupPublicKey else { return }
        guard let thread: SessionThread = try? SessionThread.fetchOne(db, id: groupPublicKey) else {
            return SNLog("Ignoring closed group update for nonexistent group.")
        }
        guard let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db) else { return }
        
        // Check that the message isn't from before the group was created
        guard Double(message.sentTimestamp ?? 0) > closedGroup.formationTimestamp else {
            return SNLog("Ignoring closed group update from before thread was created.")
        }
        
        guard let sender: String = message.sender else { return }
        guard let members: [GroupMember] = try? closedGroup.members.fetchAll(db) else { return }
        
        // Check that the sender is a member of the group
        guard members.contains(where: { $0.profileId == sender }) else {
            return SNLog("Ignoring closed group update from non-member.")
        }
        
        try update(groupPublicKey, sender, thread, closedGroup)
    }
    
    // MARK: - Message Requests
    
    private static func updateContactApprovalStatusIfNeeded(
        _ db: Database,
        senderSessionId: String,
        threadId: String?,
        forceConfigSync: Bool
    ) throws {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        // If the sender of the message was the current user
        if senderSessionId == userPublicKey {
            // Retrieve the contact for the thread the message was sent to (excluding 'NoteToSelf'
            // threads) and if the contact isn't flagged as approved then do so
            guard
                let threadId: String = threadId,
                let thread: SessionThread = try? SessionThread.fetchOne(db, id: threadId),
                !thread.isNoteToSelf(db),
                let contact: Contact = try? thread.contact.fetchOne(db),
                !contact.isApproved
            else { return }
            
            try? contact
                .with(isApproved: true)
                .update(db)
        }
        else {
            // The message was sent to the current user so flag their 'didApproveMe' as true (can't send a message to
            // someone without approving them)
            guard
                let contact: Contact = try? Contact.fetchOne(db, id: senderSessionId),
                !contact.didApproveMe
            else { return }

            try? contact
                .with(didApproveMe: true)
                .update(db)
        }
        
        // Force a config sync to ensure all devices know the contact approval state if desired
        guard forceConfigSync else { return }
        
        try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
    }
    
    private static func handleMessageRequestResponse(_ db: Database, _ message: MessageRequestResponse) throws {
        let userPublicKey = getUserHexEncodedPublicKey(db)
        
        // Ignore messages which were sent from the current user
        guard message.sender != userPublicKey else { return }
        guard let senderId: String = message.sender else { return }
        
        // Get the existing thead and notify the user
        if let thread: SessionThread = try? SessionThread.fetchOne(db, id: senderId) {
            _ = try Interaction(
                serverHash: message.serverHash,
                threadId: thread.id,
                authorId: senderId,
                variant: .infoMessageRequestAccepted,
                timestampMs: (
                    message.sentTimestamp.map { Int64($0) } ??
                    Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            ).inserted(db)
        }
        
        try updateContactApprovalStatusIfNeeded(
            db,
            senderSessionId: senderId,
            threadId: nil,
            forceConfigSync: true
        )
    }
}
