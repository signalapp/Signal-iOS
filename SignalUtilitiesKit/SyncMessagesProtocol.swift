import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • For write transactions, consider making it the caller's responsibility to manage the database transaction (this helps avoid unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases in which a function will be used
// • Express those cases in tests.

@objc(LKSyncMessagesProtocol)
public final class SyncMessagesProtocol : NSObject {

    /// Only ever modified from the message processing queue (`OWSBatchMessageProcessor.processingQueue`).
    private static var syncMessageTimestamps: [String:Set<UInt64>] = [:]

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: - Error

    @objc(LKSyncMessagesProtocolError)
    public class SyncMessagesProtocolError : NSError { // Not called `Error` for Obj-C interoperablity

        @objc public static let privateKeyMissing = SyncMessagesProtocolError(domain: "SyncMessagesProtocolErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "Couldn't get private key for SSK based closed group." ])
    }

    // MARK: - Sending

    @objc public static func syncProfile() {
        Storage.writeSync { transaction in
            let userPublicKey = getUserHexEncodedPublicKey()
            let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: userPublicKey, in: transaction)
            for device in userLinkedDevices {
                guard device != userPublicKey else { continue }
                let thread = TSContactThread.getOrCreateThread(withContactId: device, transaction: transaction)
                thread.save(with: transaction)
                let syncMessage = OWSOutgoingSyncMessage(in: thread, messageBody: "", attachmentId: nil)
                syncMessage.save(with: transaction)
                let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
                messageSenderJobQueue.add(message: syncMessage, transaction: transaction)
            }
        }
    }

    @objc(syncContactWithPublicKey:)
    public static func syncContact(_ publicKey: String) -> AnyPromise {
        let syncManager = SSKEnvironment.shared.syncManager
        return syncManager.syncContacts(for: [ SignalAccount(recipientId: publicKey) ])
    }

    private static func getContactsToSync(using transaction: YapDatabaseReadTransaction) -> Set<String> {
        return Set(TSContactThread.allObjectsInCollection().compactMap { $0 as? TSContactThread }
            .filter { $0.shouldThreadBeVisible }
            .map { $0.contactIdentifier() }
            .filter { ECKeyPair.isValidHexEncodedPublicKey(candidate: $0) }
            .filter { storage.getMasterHexEncodedPublicKey(for: $0, in: transaction) == nil } // Exclude secondary devices
            .filter { !LokiDatabaseUtilities.isUserLinkedDevice($0, transaction: transaction) })
    }

    @objc public static func syncAllContacts() -> AnyPromise {
        var publicKeys: [String] = []
        storage.dbReadConnection.read { transaction in
            publicKeys = [String](getContactsToSync(using: transaction))
        }
        let accounts = Set(publicKeys).map { SignalAccount(recipientId: $0) }
        let syncManager = SSKEnvironment.shared.syncManager
        let promises = accounts.chunked(by: 3).map { accounts -> Promise<Void> in // TODO: Does this always fit?
            return Promise(syncManager.syncContacts(for: accounts)).map2 { _ in }
        }
        return AnyPromise.from(when(fulfilled: promises))
    }

    @objc(syncClosedGroup:transaction:)
    public static func syncClosedGroup(_ thread: TSGroupThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        // Prepare
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        let group = thread.groupModel
        let groupPublicKey = LKGroupUtilities.getDecodedGroupID(group.groupId)
        let name = group.groupName!
        let members = group.groupMemberIds.map { Data(hex: $0) }
        let admins = group.groupAdminIds.map { Data(hex: $0) }
        guard let groupPrivateKey = Storage.getClosedGroupPrivateKey(for: groupPublicKey) else {
            print("[Loki] Couldn't get private key for SSK based closed group.")
            return AnyPromise.from(Promise<Void>(error: SyncMessagesProtocolError.privateKeyMissing))
        }
        // Generate ratchets for the user's linked devices
        let userPublicKey = getUserHexEncodedPublicKey()
        let masterPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey
        let deviceLinks = storage.getDeviceLinks(for: masterPublicKey, in: transaction)
        let linkedDevices = deviceLinks.flatMap { [ $0.master.publicKey, $0.slave.publicKey ] }.filter { $0 != userPublicKey }
        let senderKeys: [ClosedGroupSenderKey] = linkedDevices.map { publicKey in
            let ratchet = SharedSenderKeysImplementation.shared.generateRatchet(for: groupPublicKey, senderPublicKey: publicKey, using: transaction)
            return ClosedGroupSenderKey(chainKey: Data(hex: ratchet.chainKey), keyIndex: ratchet.keyIndex, publicKey: Data(hex: publicKey))
        }
        // Send a closed group update message to the existing members with the linked devices' ratchets (this message is aimed at the group)
        func sendMessageToGroup() {
            let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.info(groupPublicKey: Data(hex: groupPublicKey), name: name, senderKeys: senderKeys,
                members: members, admins: admins)
            let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
            messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        }
        sendMessageToGroup()
        // Send closed group update messages to the linked devices using established channels
        func sendMessageToLinkedDevices() {
            var allSenderKeys = Storage.getAllClosedGroupSenderKeys(for: groupPublicKey)
            allSenderKeys.formUnion(senderKeys)
            let thread = TSContactThread.getOrCreateThread(withContactId: masterPublicKey, transaction: transaction)
            thread.save(with: transaction)
            let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.new(groupPublicKey: Data(hex: groupPublicKey), name: name,
                groupPrivateKey: Data(hex: groupPrivateKey), senderKeys: [ClosedGroupSenderKey](allSenderKeys), members: members, admins: admins)
            let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
            messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction) // This internally takes care of multi device
        }
        sendMessageToLinkedDevices()
        // Return a dummy promise
        return AnyPromise.from(Promise<Void> { $0.fulfill(()) })
    }

    @objc public static func syncAllClosedGroups() -> AnyPromise {
        var closedGroups: [TSGroupThread] = []
        TSGroupThread.enumerateCollectionObjects { object, _ in
            guard let closedGroup = object as? TSGroupThread, closedGroup.groupModel.groupType == .closedGroup,
                closedGroup.shouldThreadBeVisible else { return }
            closedGroups.append(closedGroup)
        }
        let syncManager = SSKEnvironment.shared.syncManager
        let promises = closedGroups.map { group -> Promise<Void> in
            return Promise(syncManager.syncGroup(for: group)).map2 { _ in }
        }
        return AnyPromise.from(when(fulfilled: promises))
    }

    @objc public static func syncAllOpenGroups() -> AnyPromise {
        let openGroupSyncMessage = SyncOpenGroupsMessage()
        let (promise, seal) = Promise<Void>.pending()
        let messageSender = SSKEnvironment.shared.messageSender
        messageSender.send(openGroupSyncMessage, success: {
            seal.fulfill(())
        }, failure: { error in
            seal.reject(error)
        })
        return AnyPromise.from(promise)
    }

    // MARK: - Receiving

    @objc(isValidSyncMessage:transaction:)
    public static func isValidSyncMessage(_ envelope: SSKProtoEnvelope, transaction: YapDatabaseReadTransaction) -> Bool {
        let publicKey = envelope.source! // Set during UD decryption
        return LokiDatabaseUtilities.isUserLinkedDevice(publicKey, transaction: transaction)
    }

    public static func dropFromSyncMessageTimestampCache(_ timestamp: UInt64, for publicKey: String) {
        var timestamps: Set<UInt64> = syncMessageTimestamps[publicKey] ?? []
        if timestamps.contains(timestamp) { timestamps.remove(timestamp) }
        syncMessageTimestamps[publicKey] = timestamps
    }

    @objc(isDuplicateSyncMessage:fromPublicKey:)
    public static func isDuplicateSyncMessage(_ protoContent: SSKProtoContent, from publicKey: String) -> Bool {
        guard let syncMessage = protoContent.syncMessage?.sent else { return false }
        var timestamps: Set<UInt64> = syncMessageTimestamps[publicKey] ?? []
        let hasTimestamp = syncMessage.timestamp != 0
        guard hasTimestamp else { return false }
        let result = timestamps.contains(syncMessage.timestamp)
        timestamps.insert(syncMessage.timestamp)
        syncMessageTimestamps[publicKey] = timestamps
        return result
    }

    @objc(updateProfileFromSyncMessageIfNeeded:wrappedIn:transaction:)
    public static func updateProfileFromSyncMessageIfNeeded(_ dataMessage: SSKProtoDataMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        let publicKey = envelope.source! // Set during UD decryption
        guard let userMasterPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (userMasterPublicKey == publicKey)
        guard wasSentByMasterDevice else { return }
        SessionMetaProtocol.updateDisplayNameIfNeeded(for: userMasterPublicKey, using: dataMessage, in: transaction)
        SessionMetaProtocol.updateProfileKeyIfNeeded(for: userMasterPublicKey, using: dataMessage)
    }

    /// - Note: Deprecated.
    @objc(handleClosedGroupUpdateSyncMessageIfNeeded:wrappedIn:transaction:)
    public static func handleClosedGroupUpdateSyncMessageIfNeeded(_ transcript: OWSIncomingSentMessageTranscript, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // Check preconditions
        let publicKey = envelope.source! // Set during UD decryption
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        let wasSentByLinkedDevice = userLinkedDevices.contains(publicKey)
        guard wasSentByLinkedDevice, let group = transcript.dataMessage.group, let name = group.name else { return }
        // Create or update the group
        let id = group.id
        let members = group.members
        let newGroupThread = TSGroupThread.getOrCreateThread(withGroupId: id, groupType: .closedGroup, transaction: transaction)
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: id, groupType: .closedGroup, adminIds: group.admins)
        newGroupThread.save(with: transaction)
        newGroupThread.setGroupModel(newGroupModel, with: transaction)
        OWSDisappearingMessagesJob.shared().becomeConsistent(withDisappearingDuration: transcript.dataMessage.expireTimer, thread: newGroupThread, createdByRemoteRecipientId: nil, createdInExistingGroup: true, transaction: transaction)
        // Try to establish sessions with all members for which none exists yet when a group is created or updated
        ClosedGroupsProtocol.establishSessionsIfNeeded(with: members, using: transaction)
        // Notify the user
        let contactsManager = SSKEnvironment.shared.contactsManager
        let infoMessageText = newGroupThread.groupModel.getInfoStringAboutUpdate(to: newGroupModel, contactsManager: contactsManager)
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: newGroupThread, messageType: .typeGroupUpdate, customMessage: infoMessageText)
        infoMessage.save(with: transaction)
    }

    /// - Note: Deprecated.
    @objc(handleClosedGroupQuitSyncMessageIfNeeded:wrappedIn:transaction:)
    public static func handleClosedGroupQuitSyncMessageIfNeeded(_ transcript: OWSIncomingSentMessageTranscript, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // Check preconditions
        let publicKey = envelope.source! // Set during UD decryption
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        let wasSentByLinkedDevice = userLinkedDevices.contains(publicKey)
        guard wasSentByLinkedDevice, let group = transcript.dataMessage.group else { return }
        // Leave the group
        let groupThread = TSGroupThread.getOrCreateThread(withGroupId: group.id, groupType: .closedGroup, transaction: transaction)
        groupThread.save(with: transaction)
        groupThread.leaveGroup(with: transaction)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: groupThread, messageType: .typeGroupQuit, customMessage: NSLocalizedString("GROUP_YOU_LEFT", comment: ""))
        infoMessage.save(with: transaction)
    }

    @objc(handleContactSyncMessageIfNeeded:wrappedIn:transaction:)
    public static func handleContactSyncMessageIfNeeded(_ syncMessage: SSKProtoSyncMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        let publicKey = envelope.source! // Set during UD decryption
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        let wasSentByLinkedDevice = userLinkedDevices.contains(publicKey)
        guard wasSentByLinkedDevice, let contacts = syncMessage.contacts, let contactsAsData = contacts.data, !contactsAsData.isEmpty else { return }
        print("[Loki] Contact sync message received.")
        handleContactSyncMessageData(contactsAsData, using: transaction)
    }

    public static func handleContactSyncMessageData(_ data: Data, using transaction: YapDatabaseReadWriteTransaction) {
        let parser = ContactParser(data: data)
        let tuples = parser.parse()
        let blockedPublicKeys = tuples.filter { $0.isBlocked }.map { $0.publicKey }
        let userPublicKey = getUserHexEncodedPublicKey()
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: userPublicKey, in: transaction)
        // Try to establish sessions
        for (publicKey, isBlocked) in tuples {
            guard !userLinkedDevices.contains(publicKey) else { continue } // Skip self and linked devices
            let thread = TSContactThread.getOrCreateThread(withContactId: publicKey, transaction: transaction)
            thread.shouldThreadBeVisible = true
            thread.save(with: transaction)
            if !isBlocked {
                SessionManagementProtocol.sendSessionRequestIfNeeded(to: publicKey, using: transaction)
            }
        }
        // Update the blocked contacts list
        transaction.addCompletionQueue(DispatchQueue.main) {
            SSKEnvironment.shared.blockingManager.setBlockedPhoneNumbers(blockedPublicKeys, sendSyncMessage: false)
            NotificationCenter.default.post(name: .blockedContactsUpdated, object: nil)
        }
    }

    /// - Note: Deprecated.
    @objc(handleClosedGroupSyncMessageIfNeeded:wrappedIn:transaction:)
    public static func handleClosedGroupSyncMessageIfNeeded(_ syncMessage: SSKProtoSyncMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        let publicKey = envelope.source! // Set during UD decryption
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        let wasSentByLinkedDevice = userLinkedDevices.contains(publicKey)
        guard wasSentByLinkedDevice, let groups = syncMessage.groups, let groupsAsData = groups.data, !groupsAsData.isEmpty else { return }
        print("[Loki] Closed group sync message received.")
        let parser = ClosedGroupParser(data: groupsAsData)
        let closedGroups = parser.parseGroupModels()
        for closedGroup in closedGroups {
            var thread: TSGroupThread! = TSGroupThread(groupId: closedGroup.groupId, transaction: transaction)
            if thread == nil {
                thread = TSGroupThread.getOrCreateThread(with: closedGroup, transaction: transaction)
                thread.shouldThreadBeVisible = true
                thread.save(with: transaction)
            }
            ClosedGroupsProtocol.establishSessionsIfNeeded(with: closedGroup.groupMemberIds, using: transaction)
        }
    }

    @objc(handleOpenGroupSyncMessageIfNeeded:wrappedIn:transaction:)
    public static func handleOpenGroupSyncMessageIfNeeded(_ syncMessage: SSKProtoSyncMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        let publicKey = envelope.source! // Set during UD decryption
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        let wasSentByLinkedDevice = userLinkedDevices.contains(publicKey)
        guard wasSentByLinkedDevice else { return }
        let openGroups = syncMessage.openGroups
        guard !openGroups.isEmpty else { return }
        print("[Loki] Open group sync message received.")
        let openGroupManager = PublicChatManager.shared
        let userPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] ?? getUserHexEncodedPublicKey()
        let userDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: userPublicKey, transaction: transaction)
        for openGroup in openGroups {
            guard openGroupManager.getChat(server: openGroup.url, channel: openGroup.channelID) == nil else { return }
            openGroupManager.addChat(server: openGroup.url, channel: openGroup.channelID)
            OpenGroupAPI.setDisplayName(to: userDisplayName, on: openGroup.url)
            // TODO: Should we also set the profile picture here?
        }
    }
}
