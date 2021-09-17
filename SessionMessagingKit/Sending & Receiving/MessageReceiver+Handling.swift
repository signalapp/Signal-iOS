import SignalCoreKit
import SessionSnodeKit

extension MessageReceiver {

    internal static func isBlocked(_ publicKey: String) -> Bool {
        return SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(publicKey)
    }

    public static func handle(_ message: Message, associatedWithProto proto: SNProtoContent, openGroupID: String?, isBackgroundPoll: Bool, using transaction: Any) throws {
        switch message {
        case let message as ReadReceipt: handleReadReceipt(message, using: transaction)
        case let message as TypingIndicator: handleTypingIndicator(message, using: transaction)
        case let message as ClosedGroupControlMessage: handleClosedGroupControlMessage(message, using: transaction)
        case let message as DataExtractionNotification: handleDataExtractionNotification(message, using: transaction)
        case let message as ExpirationTimerUpdate: handleExpirationTimerUpdate(message, using: transaction)
        case let message as ConfigurationMessage: handleConfigurationMessage(message, using: transaction)
        case let message as UnsendRequest: handleUnsendRequest(message, using: transaction)
        case let message as VisibleMessage: try handleVisibleMessage(message, associatedWithProto: proto, openGroupID: openGroupID, isBackgroundPoll: isBackgroundPoll, using: transaction)
        default: fatalError()
        }
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        guard isMainAppAndActive else { return }
        // Touch the thread to update the home screen preview
        let storage = SNMessagingKitConfiguration.shared.storage
        guard let threadID = storage.getOrCreateThread(for: message.sender!, groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { return }
        ThreadUpdateBatcher.shared.touch(threadID)
    }

    
    
    // MARK: - Read Receipts
    
    private static func handleReadReceipt(_ message: ReadReceipt, using transaction: Any) {
        SSKEnvironment.shared.readReceiptManager.processReadReceipts(fromRecipientId: message.sender!, sentTimestamps: message.timestamps!.map { NSNumber(value: $0) }, readTimestamp: message.receivedTimestamp!)
    }

    
    
    // MARK: - Typing Indicators
    
    private static func handleTypingIndicator(_ message: TypingIndicator, using transaction: Any) {
        switch message.kind! {
        case .started: showTypingIndicatorIfNeeded(for: message.sender!)
        case .stopped: hideTypingIndicatorIfNeeded(for: message.sender!)
        }
    }

    public static func showTypingIndicatorIfNeeded(for senderPublicKey: String) {
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

    public static func hideTypingIndicatorIfNeeded(for senderPublicKey: String) {
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
    
    private static func handleDataExtractionNotification(_ message: DataExtractionNotification, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard message.groupPublicKey == nil,
            let thread = TSContactThread.getWithContactSessionID(message.sender!, transaction: transaction) else { return }
        let type: TSInfoMessageType
        switch message.kind! {
        case .screenshot: type = .screenshotNotification
        case .mediaSaved: type = .mediaSavedNotification
        }
        let message = DataExtractionNotificationInfoMessage(type: type, sentTimestamp: message.sentTimestamp!, thread: thread, referencedAttachmentTimestamp: nil)
        message.save(with: transaction)
    }
    
    
    
    // MARK: - Expiration Timers

    private static func handleExpirationTimerUpdate(_ message: ExpirationTimerUpdate, using transaction: Any) {
        if message.duration! > 0 {
            setExpirationTimer(to: message.duration!, for: message.sender!, syncTarget: message.syncTarget, groupPublicKey: message.groupPublicKey, messageSentTimestamp: message.sentTimestamp!, using: transaction)
        } else {
            disableExpirationTimer(for: message.sender!, syncTarget: message.syncTarget, groupPublicKey: message.groupPublicKey, messageSentTimestamp: message.sentTimestamp!, using: transaction)
        }
    }

    public static func setExpirationTimer(to duration: UInt32, for senderPublicKey: String, syncTarget: String?, groupPublicKey: String?, messageSentTimestamp: UInt64, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getWithContactSessionID(syncTarget ?? senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: true, durationSeconds: duration)
        configuration.save(with: transaction)
        var senderDisplayName: String? = nil
        if senderPublicKey != getUserHexEncodedPublicKey() {
            senderDisplayName = Storage.shared.getContact(with: senderPublicKey)?.displayName(for: .regular) ?? senderPublicKey
        }
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: messageSentTimestamp, thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

    public static func disableExpirationTimer(for senderPublicKey: String, syncTarget: String?, groupPublicKey: String?, messageSentTimestamp: UInt64, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getWithContactSessionID(syncTarget ?? senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: false, durationSeconds: 24 * 60 * 60)
        configuration.save(with: transaction)
        var senderDisplayName: String? = nil
        if senderPublicKey != getUserHexEncodedPublicKey() {
            senderDisplayName = Storage.shared.getContact(with: senderPublicKey)?.displayName(for: .regular) ?? senderPublicKey
        }
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: messageSentTimestamp, thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }
    
    
    
    // MARK: - Configuration Messages
    
    private static func handleConfigurationMessage(_ message: ConfigurationMessage, using transaction: Any) {
        let userPublicKey = getUserHexEncodedPublicKey()
        guard message.sender == userPublicKey else { return }
        SNLog("Configuration message received.")
        let storage = SNMessagingKitConfiguration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Profile
        var userProfileKy: OWSAES256Key? = nil
        if let profileKey = message.profileKey { userProfileKy = OWSAES256Key(data: profileKey) }
        updateProfileIfNeeded(publicKey: userPublicKey, name: message.displayName, profilePictureURL: message.profilePictureURL,
            profileKey: userProfileKy, sentTimestamp: message.sentTimestamp!, transaction: transaction)
        // Initial configuration sync
        if !UserDefaults.standard[.hasSyncedInitialConfiguration] {
            UserDefaults.standard[.hasSyncedInitialConfiguration] = true
            NotificationCenter.default.post(name: .initialConfigurationMessageReceived, object: nil)
            // Contacts
            for contactInfo in message.contacts {
                let sessionID = contactInfo.publicKey!
                let contact = Contact(sessionID: sessionID)
                if let profileKey = contactInfo.profileKey { contact.profileEncryptionKey = OWSAES256Key(data: profileKey) }
                contact.profilePictureURL = contactInfo.profilePictureURL
                contact.name = contactInfo.displayName
                Storage.shared.setContact(contact, using: transaction)
                let thread = TSContactThread.getOrCreateThread(withContactSessionID: sessionID, transaction: transaction)
                thread.shouldBeVisible = true
                thread.save(with: transaction)
            }
            // Closed groups
            let allClosedGroupPublicKeys = storage.getUserClosedGroupPublicKeys()
            for closedGroup in message.closedGroups {
                guard !allClosedGroupPublicKeys.contains(closedGroup.publicKey) else { continue }
                handleNewClosedGroup(groupPublicKey: closedGroup.publicKey, name: closedGroup.name, encryptionKeyPair: closedGroup.encryptionKeyPair,
                    members: [String](closedGroup.members), admins: [String](closedGroup.admins), expirationTimer: closedGroup.expirationTimer,
                    messageSentTimestamp: message.sentTimestamp!, using: transaction)
            }
            // Open groups
            for openGroupURL in message.openGroups {
                if let (room, server, publicKey) = OpenGroupManagerV2.parseV2OpenGroup(from: openGroupURL) {
                    OpenGroupManagerV2.shared.add(room: room, server: server, publicKey: publicKey, using: transaction).retainUntilComplete()
                }
            }
        }
    }
    
    
    
    // MARK: - Unsend Requests
    
    public static func handleUnsendRequest(_ message: UnsendRequest, using transaction: Any) {
        guard message.sender == message.author else { return }
        let userPublicKey = getUserHexEncodedPublicKey()
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        if let author = message.author, let timestamp = message.timestamp {
            let localMessage: TSMessage?
            if userPublicKey == message.sender {
                localMessage = TSOutgoingMessage.find(withTimestamp: timestamp)
            } else {
                localMessage = TSIncomingMessage.find(withAuthorId: author, timestamp: timestamp, transaction: transaction)
            }
            if let messageToDelete = localMessage {
                if let incomingMessage = messageToDelete as? TSIncomingMessage {
                    incomingMessage.markAsReadNow(withSendReadReceipt: false, transaction: transaction)
                    if let notificationIdentifier = incomingMessage.notificationIdentifier, !notificationIdentifier.isEmpty {
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
                    }
                }
                if let serverHash = messageToDelete.serverHash {
                    SnodeAPI.deleteMessage(publicKey: author, serverHashes: [serverHash]).retainUntilComplete()
                }
                messageToDelete.updateForDeletion(with: transaction)
            }
        }
    }
    
    
    
    // MARK: - Visible Messages

    @discardableResult
    public static func handleVisibleMessage(_ message: VisibleMessage, associatedWithProto proto: SNProtoContent, openGroupID: String?, isBackgroundPoll: Bool, using transaction: Any) throws -> String {
        let storage = SNMessagingKitConfiguration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        // Parse & persist attachments
        let attachments: [VisibleMessage.Attachment] = proto.dataMessage!.attachments.compactMap { proto in
            guard let attachment = VisibleMessage.Attachment.fromProto(proto) else { return nil }
            return attachment.isValid ? attachment : nil
        }
        let attachmentIDs = storage.persist(attachments, using: transaction)
        message.attachmentIDs = attachmentIDs
        var attachmentsToDownload = attachmentIDs
        // Update profile if needed
        if let profile = message.profile {
            let sessionID = message.sender!
            updateProfileIfNeeded(publicKey: sessionID, name: profile.displayName, profilePictureURL: profile.profilePictureURL,
                profileKey: given(profile.profileKey) { OWSAES256Key(data: $0)! }, sentTimestamp: message.sentTimestamp!, transaction: transaction)
        }
        // Get or create thread
        guard let threadID = storage.getOrCreateThread(for: message.syncTarget ?? message.sender!, groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { throw Error.noThread }
        // Parse quote if needed
        var tsQuotedMessage: TSQuotedMessage? = nil
        if message.quote != nil && proto.dataMessage?.quote != nil, let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) {
            tsQuotedMessage = TSQuotedMessage(for: proto.dataMessage!, thread: thread, transaction: transaction)
            if let id = tsQuotedMessage?.thumbnailAttachmentStreamId() ?? tsQuotedMessage?.thumbnailAttachmentPointerId() {
                attachmentsToDownload.append(id)
            }
        }
        // Parse link preview if needed
        var owsLinkPreview: OWSLinkPreview?
        if message.linkPreview != nil && proto.dataMessage?.preview.isEmpty == false {
            owsLinkPreview = try? OWSLinkPreview.buildValidatedLinkPreview(dataMessage: proto.dataMessage!, body: message.text, transaction: transaction)
            if let id = owsLinkPreview?.imageAttachmentId {
                attachmentsToDownload.append(id)
            }
        }
        // Persist the message
        guard let tsMessageID = storage.persist(message, quotedMessage: tsQuotedMessage, linkPreview: owsLinkPreview,
            groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { throw Error.noThread }
        message.threadID = threadID
        // Start attachment downloads if needed
        let isContactTrusted = Storage.shared.getContact(with: message.sender!)?.isTrusted ?? false
        let isGroup = message.groupPublicKey != nil || openGroupID != nil
        attachmentsToDownload.forEach { attachmentID in
            let downloadJob = AttachmentDownloadJob(attachmentID: attachmentID, tsMessageID: tsMessageID, threadID: threadID)
            downloadJob.isDeferred = !isContactTrusted && !isGroup
            if isMainAppAndActive {
                JobQueue.shared.add(downloadJob, using: transaction)
            } else {
                JobQueue.shared.addWithoutExecuting(downloadJob, using: transaction)
            }
        }
        // Cancel any typing indicators if needed
        if isMainAppAndActive {
            cancelTypingIndicatorsIfNeeded(for: message.sender!)
        }
        // Keep track of the open group server message ID ↔ message ID relationship
        if let serverID = message.openGroupServerMessageID, let tsMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction) {
            tsMessage.openGroupServerMessageID = serverID
            tsMessage.save(with: transaction)
        }
        if let tsOutgoingMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction) as? TSOutgoingMessage,
            let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) {
            // Mark previous messages as read if there is a sync message
            OWSReadReceiptManager.shared().markAsReadLocally(beforeSortId: tsOutgoingMessage.sortId, thread: thread)
            // Start expiration for sync messages
            OWSDisappearingMessagesJob.shared().startAnyExpiration(for: tsOutgoingMessage, expirationStartedAt: NSDate.millisecondTimestamp(), transaction: transaction)
        }
        // Notify the user if needed
        guard (isMainAppAndActive || isBackgroundPoll), let tsIncomingMessage = TSMessage.fetch(uniqueId: tsMessageID, transaction: transaction) as? TSIncomingMessage,
            let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return tsMessageID }
        tsIncomingMessage.setNotificationIdentifier(UUID().uuidString, transaction: transaction)
        DispatchQueue.main.async {
            Storage.read { transaction in
                SSKEnvironment.shared.notificationsManager!.notifyUser(for: tsIncomingMessage, in: thread, transaction: transaction)
            }
        }
        return tsMessageID
    }
    
    
    
    // MARK: - Profile Updating
    private static func updateProfileIfNeeded(publicKey: String, name: String?, profilePictureURL: String?,
        profileKey: OWSAES256Key?, sentTimestamp: UInt64, transaction: YapDatabaseReadWriteTransaction) {
        let isCurrentUser = (publicKey == getUserHexEncodedPublicKey())
        let userDefaults = UserDefaults.standard
        let contact = Storage.shared.getContact(with: publicKey) ?? Contact(sessionID: publicKey) // New API
        // Name
        if let name = name, name != contact.name {
            let shouldUpdate: Bool
            if isCurrentUser {
                shouldUpdate = given(userDefaults[.lastDisplayNameUpdate]) { sentTimestamp > UInt64($0.timeIntervalSince1970 * 1000) } ?? true
            } else {
                shouldUpdate = true
            }
            if shouldUpdate {
                if isCurrentUser {
                    userDefaults[.lastDisplayNameUpdate] = Date(timeIntervalSince1970: TimeInterval(sentTimestamp / 1000))
                }
                contact.name = name
            }
        }
        // Profile picture & profile key
        if let profileKey = profileKey, let profilePictureURL = profilePictureURL,
            profileKey.keyData.count == kAES256_KeyByteLength, profileKey != contact.profileEncryptionKey {
            let shouldUpdate: Bool
            if isCurrentUser {
                shouldUpdate = given(userDefaults[.lastProfilePictureUpdate]) { sentTimestamp > UInt64($0.timeIntervalSince1970 * 1000) } ?? true
            } else {
                shouldUpdate = true
            }
            if shouldUpdate {
                if isCurrentUser {
                    userDefaults[.lastProfilePictureUpdate] = Date(timeIntervalSince1970: TimeInterval(sentTimestamp / 1000))
                }
                contact.profilePictureURL = profilePictureURL
                contact.profileEncryptionKey = profileKey
            }
        }
        // Persist changes
        Storage.shared.setContact(contact, using: transaction)
        // Download the profile picture if needed
        transaction.addCompletionQueue(DispatchQueue.main) {
            SSKEnvironment.shared.profileManager.downloadAvatar(forUserProfile: contact)
        }
    }

    
    
    // MARK: - Closed Groups
    private static func handleClosedGroupControlMessage(_ message: ClosedGroupControlMessage, using transaction: Any) {
        switch message.kind! {
        case .new: handleNewClosedGroup(message, using: transaction)
        case .encryptionKeyPair: handleClosedGroupEncryptionKeyPair(message, using: transaction)
        case .nameChange: handleClosedGroupNameChanged(message, using: transaction)
        case .membersAdded: handleClosedGroupMembersAdded(message, using: transaction)
        case .membersRemoved: handleClosedGroupMembersRemoved(message, using: transaction)
        case .memberLeft: handleClosedGroupMemberLeft(message, using: transaction)
        case .encryptionKeyPairRequest: handleClosedGroupEncryptionKeyPairRequest(message, using: transaction) // Currently not used
        }
    }
    
    private static func handleNewClosedGroup(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .new(publicKeyAsData, name, encryptionKeyPair, membersAsData, adminsAsData, expirationTimer) = message.kind else { return }
        let groupPublicKey = publicKeyAsData.toHexString()
        let members = membersAsData.map { $0.toHexString() }
        let admins = adminsAsData.map { $0.toHexString() }
        handleNewClosedGroup(groupPublicKey: groupPublicKey, name: name, encryptionKeyPair: encryptionKeyPair,
            members: members, admins: admins, expirationTimer: expirationTimer, messageSentTimestamp: message.sentTimestamp!, using: transaction)
    }

    private static func handleNewClosedGroup(groupPublicKey: String, name: String, encryptionKeyPair: ECKeyPair, members: [String], admins: [String], expirationTimer: UInt32, messageSentTimestamp: UInt64, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Create the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread: TSGroupThread
        if let t = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) {
            thread = t
            thread.setGroupModel(group, with: transaction)
            // Clear the zombie list if the group wasn't active
            let storage = SNMessagingKitConfiguration.shared.storage
            if !storage.isClosedGroup(groupPublicKey) {
                storage.setZombieMembers(for: groupPublicKey, to: [], using: transaction)
            }
        } else {
            thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
            thread.save(with: transaction)
            // Notify the user
            let infoMessage = TSInfoMessage(timestamp: messageSentTimestamp, in: thread, messageType: .groupCreated)
            infoMessage.save(with: transaction)
        }
        let isExpirationTimerEnabled = (expirationTimer > 0)
        let expirationTimerDuration = (isExpirationTimerEnabled ? expirationTimer : 24 * 60 * 60)
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: isExpirationTimerEnabled,
            durationSeconds: expirationTimerDuration)
        configuration.save(with: transaction)
        // Add the group to the user's set of public keys to poll for
        Storage.shared.addClosedGroupPublicKey(groupPublicKey, using: transaction)
        // Store the key pair
        Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: groupPublicKey, using: transaction)
        // Store the formation timestamp
        Storage.shared.setClosedGroupFormationTimestamp(to: messageSentTimestamp, for: groupPublicKey, using: transaction)
        // Start polling
        ClosedGroupPoller.shared.startPolling(for: groupPublicKey)
        // Notify the PN server
        let _ = PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey())
    }

    /// Extracts and adds the new encryption key pair to our list of key pairs if there is one for our public key, AND the message was
    /// sent by the group admin.
    private static func handleClosedGroupEncryptionKeyPair(_ message: ClosedGroupControlMessage, using transaction: Any) {
        // Prepare
        guard case let .encryptionKeyPair(explicitGroupPublicKey, wrappers) = message.kind,
            let groupPublicKey = explicitGroupPublicKey?.toHexString() ?? message.groupPublicKey else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let userPublicKey = getUserHexEncodedPublicKey()
        guard let userKeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else {
            return SNLog("Couldn't find user X25519 key pair.")
        }
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            return SNLog("Ignoring closed group encryption key pair for nonexistent group.")
        }
        guard thread.groupModel.groupAdminIds.contains(message.sender!) else {
            return SNLog("Ignoring closed group encryption key pair from non-admin.")
        }
        // Find our wrapper and decrypt it if possible
        guard let wrapper = wrappers.first(where: { $0.publicKey == userPublicKey }), let encryptedKeyPair = wrapper.encryptedKeyPair else { return }
        let plaintext: Data
        do {
            plaintext = try MessageReceiver.decryptWithSessionProtocol(ciphertext: encryptedKeyPair, using: userKeyPair).plaintext
        } catch {
            return SNLog("Couldn't decrypt closed group encryption key pair.")
        }
        // Parse it
        let proto: SNProtoKeyPair
        do {
            proto = try SNProtoKeyPair.parseData(plaintext)
        } catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        let keyPair: ECKeyPair
        do {
            keyPair = try ECKeyPair(publicKeyData: proto.publicKey.removing05PrefixIfNeeded(), privateKeyData: proto.privateKey)
        } catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        // Store it if needed
        let closedGroupEncryptionKeyPairs = Storage.shared.getClosedGroupEncryptionKeyPairs(for: groupPublicKey)
        guard !closedGroupEncryptionKeyPairs.contains(keyPair) else {
            return SNLog("Ignoring duplicate closed group encryption key pair.")
        }
        Storage.shared.addClosedGroupEncryptionKeyPair(keyPair, for: groupPublicKey, using: transaction)
        SNLog("Received a new closed group encryption key pair.")
    }
    
    private static func handleClosedGroupNameChanged(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .nameChange(name) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Update the group
            let newGroupModel = TSGroupModel(title: name, memberIds: group.groupMemberIds, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard name != group.groupName else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: .groupUpdated, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupMembersAdded(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .membersAdded(membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Update the group
            let addedMembers = membersAsData.map { $0.toHexString() }
            let members = Set(group.groupMemberIds).union(addedMembers)
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Send the latest encryption key pair to the added members if the current user is the admin of the group
            //
            // This fixes a race condition where:
            // • A member removes another member.
            // • A member adds someone to the group and sends them the latest group key pair.
            // • The admin is offline during all of this.
            // • When the admin comes back online they see the member removed message and generate + distribute a new key pair,
            //   but they don't know about the added member yet.
            // • Now they see the member added message.
            //
            // Without the code below, the added member(s) would never get the key pair that was generated by the admin when they saw
            // the member removed message.
            let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
            if isCurrentUserAdmin {
                for member in addedMembers {
                    MessageSender.sendLatestEncryptionKeyPair(to: member, for: message.groupPublicKey!, using: transaction)
                }
            }
            // Update zombie members in case the added members are zombies
            let storage = SNMessagingKitConfiguration.shared.storage
            let zombies = storage.getZombieMembers(for: groupPublicKey)
            if !zombies.intersection(addedMembers).isEmpty {
                storage.setZombieMembers(for: groupPublicKey, to: zombies.subtracting(addedMembers), using: transaction)
            }
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: .groupUpdated, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
 
    /// Removes the given members from the group IF
    /// • it wasn't the admin that was removed (that should happen through a `MEMBER_LEFT` message).
    /// • the admin sent the message (only the admin can truly remove members).
    /// If we're among the users that were removed, delete all encryption key pairs and the group public key, unsubscribe
    /// from push notifications for this closed group, and remove the given members from the zombie list for this group.
    private static func handleClosedGroupMembersRemoved(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .membersRemoved(membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Check that the admin wasn't removed
            let removedMembers = membersAsData.map { $0.toHexString() }
            let members = Set(group.groupMemberIds).subtracting(removedMembers)
            guard members.contains(group.groupAdminIds.first!) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            // Check that the message was sent by the group admin
            guard group.groupAdminIds.contains(message.sender!) else {
                return SNLog("Ignoring invalid closed group update.")
            }
            // If the current user was removed:
            // • Stop polling for the group
            // • Remove the key pairs associated with the group
            // • Notify the PN server
            let userPublicKey = getUserHexEncodedPublicKey()
            let wasCurrentUserRemoved = !members.contains(userPublicKey)
            if wasCurrentUserRemoved {
                Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                ClosedGroupPoller.shared.stopPolling(for: groupPublicKey)
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
            }
            let storage = SNMessagingKitConfiguration.shared.storage
            let zombies = storage.getZombieMembers(for: groupPublicKey).subtracting(removedMembers)
            storage.setZombieMembers(for: groupPublicKey, to: zombies, using: transaction)
            // Update the group
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let infoMessageType: TSInfoMessageType = wasCurrentUserRemoved ? .groupCurrentUserLeft : .groupUpdated
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: infoMessageType, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    /// If a regular member left:
    /// • Mark them as a zombie (to be removed by the admin later).
    /// If the admin left:
    /// • Unsubscribe from PNs, delete the group public key, etc. as the group will be disbanded.
    private static func handleClosedGroupMemberLeft(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case .memberLeft = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            let didAdminLeave = group.groupAdminIds.contains(message.sender!)
            let members: Set<String> = didAdminLeave ? [] : Set(group.groupMemberIds).subtracting([ message.sender! ]) // If the admin leaves the group is disbanded
            if didAdminLeave {
                // Remove the group from the database and unsubscribe from PNs
                Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
                Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey())
            } else {
                let storage = SNMessagingKitConfiguration.shared.storage
                let zombies = storage.getZombieMembers(for: groupPublicKey).union([ message.sender! ])
                storage.setZombieMembers(for: groupPublicKey, to: zombies, using: transaction)
            }
            // Update the group
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let contact = Storage.shared.getContact(with: message.sender!)
            let updateInfo: String
            if let displayName = contact?.displayName(for: Contact.Context.regular) {
                updateInfo = String(format: NSLocalizedString("GROUP_MEMBER_LEFT", comment: ""), displayName)
            } else {
                updateInfo = NSLocalizedString("GROUP_UPDATED", comment: "")
            }
            let infoMessage = TSInfoMessage(timestamp: message.sentTimestamp!, in: thread, messageType: .groupUpdated, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupEncryptionKeyPairRequest(_ message: ClosedGroupControlMessage, using transaction: Any) {
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
    
    private static func performIfValid(for message: ClosedGroupControlMessage, using transaction: Any, _ update: (Data, TSGroupThread, TSGroupModel) -> Void) {
        // Prepare
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Get the group
        guard let groupPublicKey = message.groupPublicKey else { return }
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            return SNLog("Ignoring closed group update for nonexistent group.")
        }
        let group = thread.groupModel
        // Check that the message isn't from before the group was created
        if let formationTimestamp = Storage.shared.getClosedGroupFormationTimestamp(for: groupPublicKey) {
            guard message.sentTimestamp! > formationTimestamp else {
                return SNLog("Ignoring closed group update from before thread was created.")
            }
        }
        // Check that the sender is a member of the group
        guard Set(group.groupMemberIds).contains(message.sender!) else {
            return SNLog("Ignoring closed group update from non-member.")
        }
        // Perform the update
        update(groupID, thread, group)
    }
}
