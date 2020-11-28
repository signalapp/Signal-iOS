import SessionProtocolKit
import SignalCoreKit

extension MessageReceiver {

    internal static func isBlocked(_ publicKey: String) -> Bool {
        return SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(publicKey)
    }

    internal static func handle(_ message: Message, associatedWithProto proto: SNProtoContent, using transaction: Any) throws {
        switch message {
        case let message as ReadReceipt: handleReadReceipt(message, using: transaction)
        case let message as TypingIndicator: handleTypingIndicator(message, using: transaction)
        case let message as ClosedGroupUpdate: handleClosedGroupUpdate(message, using: transaction)
        case let message as ExpirationTimerUpdate: handleExpirationTimerUpdate(message, using: transaction)
        case let message as VisibleMessage: try handleVisibleMessage(message, associatedWithProto: proto, using: transaction)
        default: fatalError()
        }
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
        var isGroup = false
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
            isGroup = true
        } else {
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: true, durationSeconds: duration)
        configuration.save(with: transaction)
        let senderDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: senderPublicKey, transaction: transaction) ?? senderPublicKey
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.millisecondTimestamp(), thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: isGroup)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

    public static func disableExpirationTimer(for senderPublicKey: String, groupPublicKey: String?, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var isGroup = false
        var threadOrNil: TSThread?
        if let groupPublicKey = groupPublicKey {
            guard Storage.shared.isClosedGroup(groupPublicKey) else { return }
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
            threadOrNil = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction)
            isGroup = true
        } else {
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: false, durationSeconds: 24 * 60 * 60)
        configuration.save(with: transaction)
        let senderDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: senderPublicKey, transaction: transaction) ?? senderPublicKey
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.millisecondTimestamp(), thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: isGroup)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

    private static func handleVisibleMessage(_ message: VisibleMessage, associatedWithProto proto: SNProtoContent, using transaction: Any) throws {
        let storage = Configuration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
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
            let oldProfile = OWSUserProfile.fetch(uniqueId: message.sender!, transaction: transaction)
            if let displayName = newProfile.displayName, displayName != oldProfile?.profileName {
                profileManager.updateProfileForContact(withID: message.sender!, displayName: displayName, with: transaction)
            }
            if let profileKey = newProfile.profileKey, let profilePictureURL = newProfile.profilePictureURL, profileKey.count == kAES256_KeyByteLength,
                profileKey != oldProfile?.profileKey?.keyData {
                profileManager.setProfileKeyData(profileKey, forRecipientId: message.sender!, avatarURL: profilePictureURL)
            }
        }
        // Get or create thread
        guard let threadID = storage.getOrCreateThread(for: message.sender!, groupPublicKey: message.groupPublicKey, using: transaction) else { throw Error.noThread }
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
            groupPublicKey: message.groupPublicKey, using: transaction) else { throw Error.noThread }
        message.threadID = threadID
        // Start attachment downloads if needed
        storage.withAsync({ transaction in
            attachmentsToDownload.forEach { attachmentID in
                let downloadJob = AttachmentDownloadJob(attachmentID: attachmentID, tsIncomingMessageID: tsIncomingMessageID)
                if CurrentAppContext().isMainAppAndActive { // This has to be called from the main thread
                    JobQueue.shared.add(downloadJob, using: transaction)
                } else {
                    JobQueue.shared.addWithoutExecuting(downloadJob, using: transaction)
                }
            }
        }, completion: { })
        // Cancel any typing indicators
        cancelTypingIndicatorsIfNeeded(for: message.sender!)
        // Notify the user if needed
        guard let tsIncomingMessage = TSIncomingMessage.fetch(uniqueId: tsIncomingMessageID, transaction: transaction), let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
        Storage.read { transaction in
            SSKEnvironment.shared.notificationsManager!.notifyUser(for: tsIncomingMessage, in: thread, transaction: transaction)
        }
    }

    private static func handleClosedGroupUpdate(_ message: ClosedGroupUpdate, using transaction: Any) {
        switch message.kind! {
        case .new: handleNewGroup(message, using: transaction)
        case .info: handleGroupUpdate(message, using: transaction)
        case .senderKeyRequest: handleSenderKeyRequest(message, using: transaction)
        case .senderKey: handleSenderKey(message, using: transaction)
        }
    }

    private static func handleNewGroup(_ message: ClosedGroupUpdate, using transaction: Any) {
        guard case let .new(groupPublicKeyAsData, name, groupPrivateKey, senderKeys, membersAsData, adminsAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let groupPublicKey = groupPublicKeyAsData.toHexString()
        let members = membersAsData.map { $0.toHexString() }
        let admins = adminsAsData.map { $0.toHexString() }
        // Persist the ratchets
        senderKeys.forEach { senderKey in
            guard members.contains(senderKey.publicKey.toHexString()) else { return }
            let ratchet = ClosedGroupRatchet(chainKey: senderKey.chainKey.toHexString(), keyIndex: UInt(senderKey.keyIndex), messageKeys: [])
            Storage.shared.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderKey.publicKey.toHexString(), ratchet: ratchet, using: transaction)
        }
        // Sort out any discrepancies between the provided sender keys and what's required
        let missingSenderKeys = Set(members).subtracting(senderKeys.map { $0.publicKey.toHexString() })
        let userPublicKey = getUserHexEncodedPublicKey()
        if missingSenderKeys.contains(userPublicKey) {
            let userRatchet = SharedSenderKeys.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
            let userSenderKey = ClosedGroupSenderKey(chainKey: Data(hex: userRatchet.chainKey), keyIndex: userRatchet.keyIndex, publicKey: Data(hex: userPublicKey))
            members.forEach { member in
                guard member != userPublicKey else { return }
                let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                thread.save(with: transaction)
                let closedGroupUpdateKind = ClosedGroupUpdate.Kind.senderKey(groupPublicKey: Data(hex: groupPublicKey), senderKey: userSenderKey)
                let closedGroupUpdate = ClosedGroupUpdate()
                closedGroupUpdate.kind = closedGroupUpdateKind
                MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
            }
        }
        missingSenderKeys.subtracting([ userPublicKey ]).forEach { publicKey in
            MessageSender.shared.requestSenderKey(for: groupPublicKey, senderPublicKey: publicKey, using: transaction)
        }
        // Create the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread: TSGroupThread
        if let t = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) {
            thread = t
            thread.setGroupModel(group, with: transaction)
        } else {
            thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
            thread.usesSharedSenderKeys = true
            thread.save(with: transaction)
        }
        // Add the group to the user's set of public keys to poll for
        Storage.shared.setClosedGroupPrivateKey(groupPrivateKey.toHexString(), for: groupPublicKey, using: transaction)
        // Notify the PN server
        let _ = PushNotificationAPI.performOperation(.subscribe, for: groupPublicKey, publicKey: getUserHexEncodedPublicKey())
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
    }

    private static func handleGroupUpdate(_ message: ClosedGroupUpdate, using transaction: Any) {
        guard case let .info(groupPublicKeyAsData, name, senderKeys, membersAsData, adminsAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let groupPublicKey = groupPublicKeyAsData.toHexString()
        let members = membersAsData.map { $0.toHexString() }
        let admins = adminsAsData.map { $0.toHexString() }
        // Get the group
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        guard let thread = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) else {
            return SNLog("Ignoring closed group info message for nonexistent group.")
        }
        let group = thread.groupModel
        // Check that the sender is a member of the group (before the update)
        guard Set(group.groupMemberIds).contains(message.sender!) else {
            return SNLog("Ignoring closed group info message from non-member.")
        }
        // Store the ratchets for any new members (it's important that this happens before the code below)
        senderKeys.forEach { senderKey in
            let ratchet = ClosedGroupRatchet(chainKey: senderKey.chainKey.toHexString(), keyIndex: UInt(senderKey.keyIndex), messageKeys: [])
            Storage.shared.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderKey.publicKey.toHexString(), ratchet: ratchet, using: transaction)
        }
        // Delete all ratchets and either:
        // • Send out the user's new ratchet using established channels if other members of the group left or were removed
        // • Remove the group from the user's set of public keys to poll for if the current user was among the members that were removed
        let oldMembers = group.groupMemberIds
        let userPublicKey = getUserHexEncodedPublicKey()
        let wasUserRemoved = !members.contains(userPublicKey)
        if Set(members).intersection(oldMembers) != Set(oldMembers) {
            let allOldRatchets = Storage.shared.getAllClosedGroupRatchets(for: groupPublicKey)
            for (senderPublicKey, oldRatchet) in allOldRatchets {
                let collection = ClosedGroupRatchetCollectionType.old
                Storage.shared.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: oldRatchet, in: collection, using: transaction)
            }
            Storage.shared.removeAllClosedGroupRatchets(for: groupPublicKey, using: transaction)
            if wasUserRemoved {
                Storage.shared.removeClosedGroupPrivateKey(for: groupPublicKey, using: transaction)
                // Notify the PN server
                let _ = PushNotificationAPI.performOperation(.unsubscribe, for: groupPublicKey, publicKey: userPublicKey)
            } else {
                let userRatchet = SharedSenderKeys.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
                let userSenderKey = ClosedGroupSenderKey(chainKey: Data(hex: userRatchet.chainKey), keyIndex: userRatchet.keyIndex, publicKey: Data(hex: userPublicKey))
                members.forEach { member in
                    guard member != userPublicKey else { return }
                    let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
                    thread.save(with: transaction)
                    let closedGroupUpdateKind = ClosedGroupUpdate.Kind.senderKey(groupPublicKey: Data(hex: groupPublicKey), senderKey: userSenderKey)
                    let closedGroupUpdate = ClosedGroupUpdate()
                    closedGroupUpdate.kind = closedGroupUpdateKind
                    MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
                }
            }
        }
        // Update the group
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        thread.setGroupModel(newGroupModel, with: transaction)
        // Notify the user if needed
        if Set(members) != Set(oldMembers) || Set(admins) != Set(group.groupAdminIds) || name != group.groupName {
            let infoMessageType: TSInfoMessageType = wasUserRemoved ? .typeGroupQuit : .typeGroupUpdate
            let updateInfo = group.getInfoStringAboutUpdate(to: newGroupModel)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: infoMessageType, customMessage: updateInfo)
            infoMessage.save(with: transaction)
        }
    }

    private static func handleSenderKeyRequest(_ message: ClosedGroupUpdate, using transaction: Any) {
        guard case let .senderKeyRequest(groupPublicKeyAsData) = message.kind else { return }
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let userPublicKey = getUserHexEncodedPublicKey()
        let groupPublicKey = groupPublicKeyAsData.toHexString()
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        guard let groupThread = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID), transaction: transaction) else {
            return SNLog("Ignoring closed group sender key request for nonexistent group.")
        }
        let group = groupThread.groupModel
        // Check that the requesting user is a member of the group
        let members = Set(group.groupMemberIds)
        guard members.contains(message.sender!) else {
            return SNLog("Ignoring closed group sender key request from non-member.")
        }
        // Respond to the request
        SNLog("Responding to sender key request from: \(message.sender!).")
        let userRatchet = Storage.shared.getClosedGroupRatchet(for: groupPublicKey, senderPublicKey: userPublicKey)
            ?? SharedSenderKeys.generateRatchet(for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
        let userSenderKey = ClosedGroupSenderKey(chainKey: Data(hex: userRatchet.chainKey), keyIndex: userRatchet.keyIndex, publicKey: Data(hex: userPublicKey))
        let thread = TSContactThread.getOrCreateThread(withContactId: message.sender!, transaction: transaction)
        thread.save(with: transaction)
        let closedGroupUpdateKind = ClosedGroupUpdate.Kind.senderKey(groupPublicKey: Data(hex: groupPublicKey), senderKey: userSenderKey)
        let closedGroupUpdate = ClosedGroupUpdate()
        closedGroupUpdate.kind = closedGroupUpdateKind
        MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
    }

    private static func handleSenderKey(_ message: ClosedGroupUpdate, using transaction: Any) {
        guard case let .senderKey(groupPublicKeyAsData, senderKey) = message.kind else { return }
        let groupPublicKey = groupPublicKeyAsData.toHexString()
        guard senderKey.publicKey.toHexString() == message.sender! else {
            return SNLog("Ignoring invalid closed group sender key.")
        }
        // Store the sender key
        SNLog("Received a sender key from: \(message.sender!).")
        let ratchet = ClosedGroupRatchet(chainKey: senderKey.chainKey.toHexString(), keyIndex: UInt(senderKey.keyIndex), messageKeys: [])
        Storage.shared.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: message.sender!, ratchet: ratchet, using: transaction)
    }
}
