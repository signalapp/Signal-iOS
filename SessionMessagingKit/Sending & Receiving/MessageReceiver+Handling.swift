// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import Curve25519Kit
import SignalCoreKit
import SessionSnodeKit

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
        
        guard (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false) else { return }
        
        // Touch the thread to update the home screen preview
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let threadID = storage.getOrCreateThread(for: message.sender!, groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { return }
        ThreadUpdateBatcher.shared.touch(threadID)
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
        switch message.kind {
            case .started: try showTypingIndicatorIfNeeded(db, for: message.sender)
            case .stopped: try hideTypingIndicatorIfNeeded(db, for: message.sender)
            
            default:
                SNLog("Unknown TypingIndicator Kind ignored")
                return
        }
    }

    private static func showTypingIndicatorIfNeeded(_ db: Database, for senderPublicKey: String?) throws {
        guard let senderPublicKey: String = senderPublicKey else { return }
        
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactSessionID(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func showTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveTypingStartedMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            showTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                showTypingIndicatorsIfNeeded()
            }
        }
    }

    private static func hideTypingIndicatorIfNeeded(_ db: Database, for senderPublicKey: String?) throws {
        guard let senderPublicKey: String = senderPublicKey else { return }
        
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactSessionID(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func hideTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveTypingStoppedMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            hideTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                hideTypingIndicatorsIfNeeded()
            }
        }
    }

    public static func cancelTypingIndicatorsIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactSessionID(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func cancelTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveIncomingMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            cancelTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                cancelTypingIndicatorsIfNeeded()
            }
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
            serverHash: message.serverHash, // TODO: Test this? (make sure it won't break anything?)
            threadId: thread.id,
            authorId: sender, // TODO: Confirm this
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
        let targetId: String? = {
            if let groupPublicKey: String = message.groupPublicKey { return groupPublicKey }
            
            return (message.syncTarget ?? message.sender)
        }()
        
        // Get the target thread
        guard
            let targetId: String = targetId,
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
                isEnabled: (message.duration != nil),
                durationSeconds: (
                    message.duration.map { TimeInterval($0) } ??
                    DisappearingMessagesConfiguration.defaultDuration
                )
            )
            .saved(db)
        
        // Add an info message for the user
        //
        // Note: If it's a duplicate message (which the 'ExpirationTimerUpdate' frequently can be)
        // then the write transaction will fail meaning the above config update won't be applied
        // so we don't need to worry about order-of-execution)
        _ = try Interaction(
            serverHash: message.serverHash,
            threadId: thread.id,
            authorId: sender,
            variant: .infoDisappearingMessagesUpdate,
            body: config.infoUpdateMessage(
                with: (sender != getUserHexEncodedPublicKey(db) ?
                    Profile.displayName(db, id: sender) :
                    nil
                )
            ),
            timestampMs: Int64(message.sentTimestamp ?? 0)   // Default to `0` if not set
        ).inserted(db)
    }
    
    // MARK: - Configuration Messages
    
    private static func handleConfigurationMessage(_ db: Database, _ message: ConfigurationMessage) throws {
        let userPublicKey = getUserHexEncodedPublicKey(db)
        
        guard message.sender == userPublicKey else { return }
        
        SNLog("Configuration message received.")
        
        // Note: `message.sentTimestamp` is in ms
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
            profilePictureUrl: message.profilePictureURL,
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
                        profilePictureUrl: .updateIf(contactInfo.profilePictureURL),
                        profileEncryptionKey: .updateIf(
                            contactInfo.profileKey.map { OWSAES256Key(data: $0) }
                        )
                    )
                    .save(db)
                
                // Note: We only update these values if the proto actually has values for them (this is to
                // prevent an edge case where an old client could override the values with default values
                // since they aren't included)
                //
                // Note: Since message requests has no reverse, the only case we need to process is a
                // config message setting *isApproved* and *didApproveMe* to true. This may prevent some
                // weird edge cases where a config message swapping *isApproved* and *didApproveMe* to
                // false.
                try contact
                    .with(
                        isApproved: (contactInfo.hasIsApproved && contactInfo.isApproved ?
                            .existing :
                            true
                        ),
                        isBlocked: (contactInfo.hasIsBlocked && contactInfo.isBlocked ?
                            .existing :
                            true
                        ),
                        didApproveMe: (contactInfo.hasDidApproveMe && contactInfo.didApproveMe ?
                            .existing :
                            true
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
                        try thread.delete(db)
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
                        publicKey: closedGroup.encryptionKeyPair.publicKey.bytes,
                        secretKey: closedGroup.encryptionKeyPair.privateKey.bytes
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
        
        guard let interaction: Interaction = maybeInteraction else { return }
        
        // Mark incoming messages as read and remove any of their notifications
        if interaction.variant == .standardIncoming {
            _ = try interaction.markingAsRead(db, includingOlder: false, trySendReadReceipt: false)
            
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: interaction.notificationIdentifiers)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: interaction.notificationIdentifiers)
        }
        
        if author == message.sender {
            if let serverHash: String = interaction.serverHash {
                SnodeAPI.deleteMessage(publicKey: author, serverHashes: [serverHash]).retainUntilComplete()
            }
            
            _ = try interaction
                .markingAsDeleted()
                .saved(db)
            
            _ = try interaction.attachments
                .deleteAll(db)
        }
        else {
            _ = try interaction.delete(db)
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
        
        // Note: `message.sentTimestamp` is in ms
        let messageSentTimestamp: TimeInterval = TimeInterval((message.sentTimestamp ?? 0) / 1000)
        let isMainAppActive: Bool = (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false)
        
        // Parse & persist attachments
        
        let attachments: [Attachment] = dataMessage.attachments
            .compactMap { proto in
                let attachment: Attachment = Attachment(proto: proto)
                
                // Attachments on received messages must have a 'downloadUrl' otherwise
                // they are invalid and we can ignore them
                return (attachment.downloadUrl != nil ? attachment : nil)
            }
        try attachments.saveAll(db)
        
        message.attachmentIDs = attachments.map { $0.id }
        
        // Update profile if needed
        if let profile = message.profile {
            var contactProfileKey: OWSAES256Key? = nil
            if let profileKey = profile.profileKey { contactProfileKey = OWSAES256Key(data: profileKey) }
            
            try updateProfileIfNeeded(
                db,
                publicKey: sender,
                name: profile.displayName,
                profilePictureUrl: profile.profilePictureURL,
                profileKey: contactProfileKey,
                sentTimestamp: messageSentTimestamp
            )
        }
        
        // Get or create thread
        let threadInfo: (id: String, variant: SessionThread.Variant)? = {
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
            
            return ((message.syncTarget ?? sender), .contact)
        }()
        guard let threadInfo: (id: String, variant: SessionThread.Variant) = threadInfo else {
            throw MessageReceiverError.noThread
        }

        let thread: SessionThread = SessionThread.fetchOrCreate(db, id: threadInfo.id, variant: threadInfo.variant)
        let interaction: Interaction
        let interactionId: Int64
        
        do {
            // Store the message variant so we can run variant-specific behaviours
            let variant: Interaction.Variant = {
                if sender == getUserHexEncodedPublicKey(db) {
                    return .standardOutgoing
                }
                
                return .standardIncoming
            }()
            
            // Check if there is an existing message with the same timestamp, variant and sender
            let existingInteraction: Interaction? = try? thread.interactions
                .filter(Interaction.Columns.timestampMs == (messageSentTimestamp * 1000))
                .filter(Interaction.Columns.variant == variant)
                .filter(Interaction.Columns.authorId == sender)
                .fetchOne(db)
                
            if let existingInteraction: Interaction = existingInteraction {
                // These values might not have been set yet for outgoing interactions so update them
                interaction = try existingInteraction
                    .with(
                        serverHash: message.serverHash, // Keep track of server hash
                        openGroupServerMessageId: message.openGroupServerMessageID.map { Int64($0) }
                    )
                    .saved(db)
                
                guard let existingInteractionId: Int64 = interaction.id else { throw GRDBStorageError.failedToSave }
                
                interactionId = existingInteractionId
            }
            else {
                let disappearingMessagesConfiguration: DisappearingMessagesConfiguration = (try? thread.disappearingMessagesConfiguration.fetchOne(db))
                    .defaulting(to: DisappearingMessagesConfiguration.defaultWith(thread.id))
                
                interaction = try Interaction(
                    serverHash: message.serverHash, // Keep track of server hash
                    threadId: thread.id,
                    authorId: sender,
                    variant: variant,
                    body: message.text,
                    timestampMs: Int64(messageSentTimestamp * 1000),
                    // Note: Ensure we don't ever expire open group messages
                    expiresInSeconds: (disappearingMessagesConfiguration.isEnabled && message.openGroupServerMessageID == nil ?
                        disappearingMessagesConfiguration.durationSeconds :
                        nil
                    ),
                    expiresStartedAtMs: nil,
                    // OpenGroupInvitations are stored as LinkPreview's in the database
                    linkPreviewUrl: (message.linkPreview?.url ?? message.openGroupInvitation?.url),
                    // Keep track of the open group server message ID ↔ message ID relationship
                    openGroupServerMessageId: message.openGroupServerMessageID.map { Int64($0) },
                    openGroupWhisperMods: false,       // TODO: SOGSV4
                    openGroupWhisperTo: nil            // TODO: SOGSV4
                ).inserted(db)
                
                guard let newInteractionId: Int64 = interaction.id else { throw GRDBStorageError.failedToSave }
                
                interactionId = newInteractionId
                
                // For newly created outgoing messages upsert the recipient states to sent
                if variant == .standardOutgoing {
                    if let syncTarget: String = message.syncTarget {
                        try RecipientState(
                            interactionId: interactionId,
                            recipientId: syncTarget,
                            state: .sent
                        ).save(db)
                    }
                    else if
                        let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db),
                        let members: [GroupMember] = try? closedGroup.members.fetchAll(db)
                    {
                        try members.forEach { member in
                            try RecipientState(
                                interactionId: interactionId,
                                recipientId: member.profileId,
                                state: .sent
                            ).save(db)
                        }
                    }
                }
            }
            
            // For outgoing messages mark it and all older interactions as read
            if variant == .standardOutgoing {
                _ = try interaction.markingAsRead(db, includingOlder: true, trySendReadReceipt: true)
            }
                
        }
        catch {
            throw error
        }
        
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
            body: message.text
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
            cancelTypingIndicatorsIfNeeded(for: message.sender!)
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
        guard interaction.variant == .standardIncoming else { return interactionId }
        
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
    
    // MARK: - Profile Updating
    
    private static func updateProfileIfNeeded(
        _ db: Database, publicKey: String,
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
            .saved(db)
        let closedGroup: ClosedGroup = try ClosedGroup(
            threadId: groupPublicKey,
            name: name,
            formationTimestamp: Date().timeIntervalSince1970
        ).saved(db)
        
        // Clear the zombie list if the group wasn't active (ie. had no keys)
        if ((try? closedGroup.keyPairs.fetchCount(db)) ?? 0) == 0 {
            try closedGroup.zombies.deleteAll(db)
        }
        
        // Notify the user
        if !groupAlreadyExisted {
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
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
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
        
        // Add the group to the user's set of public keys to poll for
        Storage.shared.addClosedGroupPublicKey(groupPublicKey, using: transaction)
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
                serverHash: message.serverHash, // TODO: Test this? (make sure it won't break anything?)
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .nameChange(name: name)
                    .infoMessage(db, sender: sender),
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
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
            let members: Set<String> = Set(groupMembers.map { $0.profileId }).union(addedMembers)
            
            try addedMembers.forEach { memberId in
                try GroupMember(
                    groupId: id,
                    profileId: memberId,
                    role: .standard
                ).save(db)
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
            
            // Update zombie members in case the added members are zombies
            let zombies: [GroupMember] = ((try? closedGroup.zombies.fetchAll(db)) ?? [])
            
            if !zombies.map { $0.profileId }.asSet().intersection(addedMembers).isEmpty {
                try zombies
                    .filter { !addedMembers.contains($0.profileId) }
                    .deleteAll(db)
            }
            
            // Notify the user if needed
            guard members != Set(groupMembers.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash, // TODO: Test this? (make sure it won't break anything?)
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
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
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
                
                _ = try closedGroup
                    .keyPairs
                    .deleteAll(db)
                let _ = PushNotificationAPI.performOperation(
                    .unsubscribe,
                    for: id,
                    publicKey: userPublicKey
                )
            }
            
            // Remove the member from the group and it's zombies
            try closedGroup.members
                .filter(removedMembers.contains(GroupMember.Columns.profileId))
                .deleteAll(db)
            try closedGroup.zombies
                .filter(removedMembers.contains(GroupMember.Columns.profileId))
                .deleteAll(db)
            
            // Notify the user if needed
            guard members != Set(groupMembers.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash, // TODO: Test this? (make sure it won't break anything?)
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
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
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
            
            if didAdminLeave {
                // Remove the group from the database and unsubscribe from PNs
                ClosedGroupPoller.shared.stopPolling(for: id)
                
                _ = try closedGroup
                    .keyPairs
                    .deleteAll(db)
                let _ = PushNotificationAPI.performOperation(
                    .unsubscribe,
                    for: id,
                    publicKey: getUserHexEncodedPublicKey(db)
                )
            }
            else {
                try GroupMember(
                    groupId: id,
                    profileId: sender,
                    role: .zombie
                ).save(db)
            }
            
            // Update the group
            try membersToRemove
                .deleteAll(db)
            
            // Notify the user if needed
            guard updatedMemberIds != Set(members.map { $0.profileId }) else { return }
            
            _ = try Interaction(
                serverHash: message.serverHash, // TODO: Test this? (make sure it won't break anything?)
                threadId: thread.id,
                authorId: sender,
                variant: .infoClosedGroupUpdated,
                body: ClosedGroupControlMessage.Kind
                    .memberLeft
                    .infoMessage(db, sender: sender),
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
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
                serverHash: message.serverHash, // TODO: Test this? (make sure it won't break anything?)
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
