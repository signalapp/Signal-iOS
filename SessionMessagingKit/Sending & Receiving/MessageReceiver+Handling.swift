import SessionProtocolKit
import SignalCoreKit

extension MessageReceiver {

    internal static func isBlocked(_ publicKey: String) -> Bool {
        return SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(publicKey)
    }

    public static func handle(_ message: Message, associatedWithProto proto: SNProtoContent, openGroupID: String?, isBackgroundPoll: Bool, using transaction: Any) throws {
        switch message {
        case let message as ReadReceipt: handleReadReceipt(message, using: transaction)
        case let message as TypingIndicator: handleTypingIndicator(message, using: transaction)
        case let message as ClosedGroupControlMessage: handleClosedGroupControlMessage(message, using: transaction)
        case let message as ExpirationTimerUpdate: handleExpirationTimerUpdate(message, using: transaction)
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
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
        thread.touch(with: transaction)
    }

    private static func handleReadReceipt(_ message: ReadReceipt, using transaction: Any) {
        SSKEnvironment.shared.readReceiptManager.processReadReceipts(fromRecipientId: message.sender!, sentTimestamps: message.timestamps!.map { NSNumber(value: $0) }, readTimestamp: message.receivedTimestamp!)
    }

    private static func handleTypingIndicator(_ message: TypingIndicator, using transaction: Any) {
        switch message.kind! {
        case .started: showTypingIndicatorIfNeeded(for: message.sender!)
        case .stopped: hideTypingIndicatorIfNeeded(for: message.sender!)
        }
    }

    public static func showTypingIndicatorIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
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
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
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
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
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

    private static func handleExpirationTimerUpdate(_ message: ExpirationTimerUpdate, using transaction: Any) {
        if message.duration! > 0 {
            setExpirationTimer(to: message.duration!, for: message.sender!, groupPublicKey: message.groupPublicKey, using: transaction)
        } else {
            disableExpirationTimer(for: message.sender!, groupPublicKey: message.groupPublicKey, using: transaction)
        }
    }

    public static func setExpirationTimer(to duration: UInt32, for senderPublicKey: String, groupPublicKey: String?, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: true, durationSeconds: duration)
        configuration.save(with: transaction)
        let senderDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: senderPublicKey, transaction: transaction) ?? senderPublicKey
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.millisecondTimestamp(), thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

    public static func disableExpirationTimer(for senderPublicKey: String, groupPublicKey: String?, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
        } else {
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: false, durationSeconds: 24 * 60 * 60)
        configuration.save(with: transaction)
        let senderDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: senderPublicKey, transaction: transaction) ?? senderPublicKey
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.millisecondTimestamp(), thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

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
        if let newProfile = message.profile {
            let profileManager = SSKEnvironment.shared.profileManager
            let sessionID = message.sender!
            let oldProfile = OWSUserProfile.fetch(uniqueId: sessionID, transaction: transaction)
            let contact = Storage.shared.getContact(with: sessionID) ?? Contact(sessionID: sessionID)
            if let displayName = newProfile.displayName, displayName != oldProfile?.profileName {
                profileManager.updateProfileForContact(withID: sessionID, displayName: displayName, with: transaction)
                contact.displayName = displayName
            }
            if let profileKey = newProfile.profileKey, let profilePictureURL = newProfile.profilePictureURL, profileKey.count == kAES256_KeyByteLength,
                profileKey != oldProfile?.profileKey?.keyData {
                profileManager.setProfileKeyData(profileKey, forRecipientId: sessionID, avatarURL: profilePictureURL)
                contact.profilePictureURL = profilePictureURL
                contact.profilePictureEncryptionKey = OWSAES256Key(data: profileKey)
            }
            if let rawDisplayName = newProfile.displayName, let openGroupID = openGroupID {
                let endIndex = sessionID.endIndex
                let cutoffIndex = sessionID.index(endIndex, offsetBy: -8)
                let displayName = "\(rawDisplayName) (...\(sessionID[cutoffIndex..<endIndex]))"
                Storage.shared.setOpenGroupDisplayName(to: displayName, for: sessionID, inOpenGroupWithID: openGroupID, using: transaction)
            }
        }
        // Get or create thread
        guard let threadID = storage.getOrCreateThread(for: message.sender!, groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { throw Error.noThread }
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
        guard let tsIncomingMessageID = storage.persist(message, quotedMessage: tsQuotedMessage, linkPreview: owsLinkPreview,
            groupPublicKey: message.groupPublicKey, openGroupID: openGroupID, using: transaction) else { throw Error.noThread }
        message.threadID = threadID
        // Start attachment downloads if needed
        attachmentsToDownload.forEach { attachmentID in
            let downloadJob = AttachmentDownloadJob(attachmentID: attachmentID, tsIncomingMessageID: tsIncomingMessageID)
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
        if let serverID = message.openGroupServerMessageID {
            storage.setIDForMessage(withServerID: serverID, to: tsIncomingMessageID, using: transaction)
        }
        // Notify the user if needed
        guard (isMainAppAndActive || isBackgroundPoll), let tsIncomingMessage = TSIncomingMessage.fetch(uniqueId: tsIncomingMessageID, transaction: transaction),
            let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return tsIncomingMessageID }
        SSKEnvironment.shared.notificationsManager!.notifyUser(for: tsIncomingMessage, in: thread, transaction: transaction)
        return tsIncomingMessageID
    }

    private static func handleClosedGroupControlMessage(_ message: ClosedGroupControlMessage, using transaction: Any) {
        switch message.kind! {
        case .new: handleNewClosedGroup(message, using: transaction)
        case .update: handleClosedGroupUpdated(message, using: transaction) // Deprecated
        case .encryptionKeyPair: handleClosedGroupEncryptionKeyPair(message, using: transaction)
        case .nameChange: handleClosedGroupNameChanged(message, using: transaction)
        case .membersAdded: handleClosedGroupMembersAdded(message, using: transaction)
        case .membersRemoved: handleClosedGroupMembersRemoved(message, using: transaction)
        case .memberLeft: handleClosedGroupMemberLeft(message, using: transaction)
        }
    }
    
    private static func handleNewClosedGroup(_ message: ClosedGroupControlMessage, using transaction: Any) {
        // Prepare
        guard case let .new(publicKeyAsData, name, encryptionKeyPair, membersAsData, adminsAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Unwrap the message
        let groupPublicKey = publicKeyAsData.toHexString()
        let members = membersAsData.map { $0.toHexString() }
        let admins = adminsAsData.map { $0.toHexString() }
        // Create the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread: TSGroupThread
        if let t = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) {
            thread = t
            thread.setGroupModel(group, with: transaction)
        } else {
            thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
            thread.save(with: transaction)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.shared.addClosedGroupPublicKey(groupPublicKey, using: transaction)
        // Store the key pair
        Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: groupPublicKey, using: transaction)
        // Notify the PN server
        let _ = PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey())
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
    }

    private static func handleClosedGroupEncryptionKeyPair(_ message: ClosedGroupControlMessage, using transaction: Any) {
        // Prepare
        guard case let .encryptionKeyPair(wrappers) = message.kind, let groupPublicKey = message.groupPublicKey else { return }
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
        let proto: SNProtoDataMessageClosedGroupControlMessageKeyPair
        do {
            proto = try SNProtoDataMessageClosedGroupControlMessageKeyPair.parseData(plaintext)
        } catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        let keyPair: ECKeyPair
        do {
            keyPair = try ECKeyPair(publicKeyData: proto.publicKey.removing05PrefixIfNeeded(), privateKeyData: proto.privateKey)
        } catch {
            return SNLog("Couldn't parse closed group encryption key pair.")
        }
        // Store it
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
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupMembersAdded(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .membersAdded(membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Update the group
            let members = Set(group.groupMemberIds).union(membersAsData.map { $0.toHexString() })
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupMembersRemoved(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case let .membersRemoved(membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            // Check that the admin wasn't removed
            let members = Set(group.groupMemberIds).subtracting(membersAsData.map { $0.toHexString() })
            guard members.contains(group.groupAdminIds.first!) else {
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
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
            }
            // Generate and distribute a new encryption key pair if needed
            let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
            if isCurrentUserAdmin {
                do {
                    try MessageSender.generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: Set(members), using: transaction)
                } catch {
                    SNLog("Couldn't distribute new encryption key pair.")
                }
            }
            // Update the group
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let infoMessageType: TSInfoMessageType = wasCurrentUserRemoved ? .typeGroupQuit : .typeGroupUpdate
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: infoMessageType, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
    
    private static func handleClosedGroupMemberLeft(_ message: ClosedGroupControlMessage, using transaction: Any) {
        guard case .memberLeft = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        guard let groupPublicKey = message.groupPublicKey else { return }
        performIfValid(for: message, using: transaction) { groupID, thread, group in
            let didAdminLeave = group.groupAdminIds.contains(message.sender!)
            let members: Set<String> = didAdminLeave ? [] : Set(group.groupMemberIds).subtracting([ message.sender! ]) // If the admin leaves the group is disbanded
            // Guard against self-sends
            guard message.sender != getUserHexEncodedPublicKey() else {
                return SNLog("Ignoring invalid closed group update.")
            }
            // Generate and distribute a new encryption key pair if needed
            let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
            if isCurrentUserAdmin {
                do {
                    try MessageSender.generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: members, using: transaction)
                } catch {
                    SNLog("Couldn't distribute new encryption key pair.")
                }
            }
            // Update the group
            let newGroupModel = TSGroupModel(title: group.groupName, memberIds: [String](members), image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
            thread.setGroupModel(newGroupModel, with: transaction)
            // Notify the user if needed
            guard members != Set(group.groupMemberIds) else { return }
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
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
        guard Double(message.sentTimestamp!) > thread.creationDate.timeIntervalSince1970 * 1000 else {
            return SNLog("Ignoring closed group update from before thread was created.")
        }
        // Check that the sender is a member of the group
        guard Set(group.groupMemberIds).contains(message.sender!) else {
            return SNLog("Ignoring closed group update from non-member.")
        }
        // Perform the update
        update(groupID, thread, group)
    }
    
    
    
    // MARK: - Deprecated
    
    /// - Note: Deprecated.
    private static func handleClosedGroupUpdated(_ message: ClosedGroupControlMessage, using transaction: Any) {
        // Prepare
        guard case let .update(name, membersAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Unwrap the message
        guard let groupPublicKey = message.groupPublicKey else { return }
        let members = membersAsData.map { $0.toHexString() }
        // Get the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let threadID = TSGroupThread.threadId(fromGroupId: groupID)
        guard let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
            return SNLog("Ignoring closed group update message for nonexistent group.")
        }
        let group = thread.groupModel
        let oldMembers = group.groupMemberIds
        // Check that the message isn't from before the group was created
        guard Double(message.sentTimestamp!) > thread.creationDate.timeIntervalSince1970 * 1000 else {
            return SNLog("Ignoring closed group update from before thread was created.")
        }
        // Check that the sender is a member of the group (before the update)
        guard Set(group.groupMemberIds).contains(message.sender!) else {
            return SNLog("Ignoring closed group update message from non-member.")
        }
        // Check that the admin wasn't removed unless the group was destroyed entirely
        if !members.contains(group.groupAdminIds.first!) && !members.isEmpty {
            return SNLog("Ignoring invalid closed group update message.")
        }
        // Remove the group from the user's set of public keys to poll for if the current user was removed
        let userPublicKey = getUserHexEncodedPublicKey()
        let wasCurrentUserRemoved = !members.contains(userPublicKey)
        if wasCurrentUserRemoved {
            Storage.shared.removeClosedGroupPublicKey(groupPublicKey, using: transaction)
            // Remove the key pairs
            Storage.shared.removeAllClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
            // Notify the PN server
            let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
        }
        // Generate and distribute a new encryption key pair if needed
        let wasAnyUserRemoved = (Set(members).intersection(oldMembers) != Set(oldMembers))
        let isCurrentUserAdmin = group.groupAdminIds.contains(getUserHexEncodedPublicKey())
        if wasAnyUserRemoved && isCurrentUserAdmin {
            do {
                try MessageSender.generateAndSendNewEncryptionKeyPair(for: groupPublicKey, to: Set(members), using: transaction)
            } catch {
                SNLog("Couldn't distribute new encryption key pair.")
            }
        }
        // Update the group
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: group.groupAdminIds)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user if needed
        if Set(members) != Set(oldMembers) || name != group.groupName {
            let infoMessageType: TSInfoMessageType = wasCurrentUserRemoved ? .typeGroupQuit : .typeGroupUpdate
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: infoMessageType, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }
}
