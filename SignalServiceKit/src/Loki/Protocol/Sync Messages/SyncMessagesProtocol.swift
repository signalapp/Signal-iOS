import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases for everything.
// • Express those cases in tests.

@objc(LKSyncMessagesProtocol)
public final class SyncMessagesProtocol : NSObject {

    /// Only ever modified from the message processing queue (`OWSBatchMessageProcessor.processingQueue`).
    private static var syncMessageTimestamps: [String:Set<UInt64>] = [:]

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: - Sending
    @objc(shouldSkipConfigurationSyncMessage)
    public static func shouldSkipConfigurationSyncMessage() -> Bool {
        // FIXME: We added this check to avoid a crash, but we should really figure out why that crash was happening in the first place
        return !UserDefaults.standard[.hasLaunchedOnce]
    }

    @objc(syncContactWithHexEncodedPublicKey:in:)
    public static func syncContact(_ hexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) {
        guard TSContactThread.getWithContactId(hexEncodedPublicKey, transaction: transaction) != nil else { return }
        let syncManager = SSKEnvironment.shared.syncManager
        syncManager.syncContacts(for: [ SignalAccount(recipientId: hexEncodedPublicKey) ])
    }

    @objc(syncAllContacts)
    public static func objc_syncAllContacts() -> AnyPromise {
        return AnyPromise.from(syncAllContacts())
    }

    public static func syncAllContacts() -> Promise<Void> {
        var friends: [SignalAccount] = []
        TSContactThread.enumerateCollectionObjects { object, _ in
            guard let thread = object as? TSContactThread else { return }
            let hexEncodedPublicKey = thread.contactIdentifier()
            guard thread.isContactFriend && thread.shouldThreadBeVisible && !thread.isForceHidden else { return }
            friends.append(SignalAccount(recipientId: hexEncodedPublicKey))
        }
        friends.append(SignalAccount(recipientId: getUserHexEncodedPublicKey())) // TODO: We sure about this?
        let syncManager = SSKEnvironment.shared.syncManager
        let promises = friends.chunked(by: 3).map { friends -> Promise<Void> in // TODO: Does this always fit?
            return Promise(syncManager.syncContacts(for: friends)).map { _ in }
        }
        return when(fulfilled: promises)
    }

    @objc(syncAllClosedGroups)
    public static func objc_syncAllClosedGroups() -> AnyPromise {
        return AnyPromise.from(syncAllClosedGroups())
    }

    public static func syncAllClosedGroups() -> Promise<Void> {
        var groups: [TSGroupThread] = []
        TSGroupThread.enumerateCollectionObjects { object, _ in
            guard let group = object as? TSGroupThread, group.groupModel.groupType == .closedGroup,
                group.shouldThreadBeVisible, !group.isForceHidden else { return }
            groups.append(group)
        }
        let syncManager = SSKEnvironment.shared.syncManager
        let promises = groups.map { group -> Promise<Void> in
            return Promise(syncManager.syncGroup(for: group)).map { _ in }
        }
        return when(fulfilled: promises)
    }

    @objc(syncAllOpenGroups)
    public static func objc_syncAllOpenGroups() -> AnyPromise {
        return AnyPromise.from(syncAllOpenGroups())
    }

    public static func syncAllOpenGroups() -> Promise<Void> {
        let openGroupSyncMessage = SyncOpenGroupsMessage()
        let (promise, seal) = Promise<Void>.pending()
        let messageSender = SSKEnvironment.shared.messageSender
        messageSender.send(openGroupSyncMessage, success: {
            seal.fulfill(())
        }, failure: { error in
            seal.reject(error)
        })
        return promise
    }

    // MARK: - Receiving
    @objc(isValidSyncMessage:in:)
    public static func isValidSyncMessage(_ envelope: SSKProtoEnvelope, in transaction: YapDatabaseReadTransaction) -> Bool {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        let linkedDeviceHexEncodedPublicKeys = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        return linkedDeviceHexEncodedPublicKeys.contains(hexEncodedPublicKey)
    }

    // TODO: We should probably look at why sync messages are being duplicated rather than doing this
    @objc(isDuplicateSyncMessage:fromHexEncodedPublicKey:)
    public static func isDuplicateSyncMessage(_ protoContent: SSKProtoContent, from hexEncodedPublicKey: String) -> Bool {
        guard let syncMessage = protoContent.syncMessage?.sent else { return false }
        var timestamps: Set<UInt64> = syncMessageTimestamps[hexEncodedPublicKey] ?? []
        let hasTimestamp = syncMessage.timestamp != 0
        guard hasTimestamp else { return false }
        let result = timestamps.contains(syncMessage.timestamp)
        timestamps.insert(syncMessage.timestamp)
        syncMessageTimestamps[hexEncodedPublicKey] = timestamps
        return result
    }

    @objc(updateProfileFromSyncMessageIfNeeded:wrappedIn:using:)
    public static func updateProfileFromSyncMessageIfNeeded(_ dataMessage: SSKProtoDataMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (masterHexEncodedPublicKey == hexEncodedPublicKey)
        guard wasSentByMasterDevice else { return }
        SessionProtocol.updateDisplayNameIfNeeded(for: masterHexEncodedPublicKey, using: dataMessage, appendingShortID: false, in: transaction)
        SessionProtocol.updateProfileKeyIfNeeded(for: masterHexEncodedPublicKey, using: dataMessage)
    }

    @objc(handleClosedGroupUpdatedSyncMessageIfNeeded:using:)
    public static func handleClosedGroupUpdatedSyncMessageIfNeeded(_ transcript: OWSIncomingSentMessageTranscript, using transaction: YapDatabaseReadWriteTransaction) {
        // TODO: This code is pretty much a duplicate of the code in OWSRecordTranscriptJob
        guard let group = transcript.dataMessage.group else { return }
        let id = group.id
        guard let name = group.name else { return }
        let members = group.members
        let admins = group.admins
        let newGroupThread = TSGroupThread.getOrCreateThread(withGroupId: id, groupType: .closedGroup, transaction: transaction)
        let newGroupModel = TSGroupModel(title: name, memberIds: members, image: nil, groupId: id, groupType: .closedGroup, adminIds: admins)
        let contactsManager = SSKEnvironment.shared.contactsManager
        let groupUpdatedMessageDescription = newGroupThread.groupModel.getInfoStringAboutUpdate(to: newGroupModel, contactsManager: contactsManager)
        newGroupThread.groupModel = newGroupModel // TODO: Should this use the setGroupModel method on TSGroupThread?
        newGroupThread.save(with: transaction)
        // Try to establish sessions with all members for which none exists yet when a group is created or updated
        ClosedGroupsProtocol.establishSessionsIfNeeded(with: members, in: newGroupThread, using: transaction)
        OWSDisappearingMessagesJob.shared().becomeConsistent(withDisappearingDuration: transcript.dataMessage.expireTimer, thread: newGroupThread, createdByRemoteRecipientId: nil, createdInExistingGroup: true, transaction: transaction)
        let groupUpdatedMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: newGroupThread, messageType: .typeGroupUpdate, customMessage: groupUpdatedMessageDescription)
        groupUpdatedMessage.save(with: transaction)
    }

    @objc(handleClosedGroupQuitSyncMessageIfNeeded:using:)
    public static func handleClosedGroupQuitSyncMessageIfNeeded(_ transcript: OWSIncomingSentMessageTranscript, using transaction: YapDatabaseReadWriteTransaction) {
        guard let group = transcript.dataMessage.group else { return }
        let groupThread = TSGroupThread.getOrCreateThread(withGroupId: group.id, groupType: .closedGroup, transaction: transaction)
        groupThread.leaveGroup(with: transaction)
        let groupQuitMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: groupThread, messageType: .typeGroupQuit, customMessage: NSLocalizedString("GROUP_YOU_LEFT", comment: ""))
        groupQuitMessage.save(with: transaction)
    }

    @objc(handleContactSyncMessageIfNeeded:wrappedIn:using:)
    public static func handleContactSyncMessageIfNeeded(_ syncMessage: SSKProtoSyncMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (masterHexEncodedPublicKey == hexEncodedPublicKey)
        guard wasSentByMasterDevice, let contacts = syncMessage.contacts, let contactsAsData = contacts.data, contactsAsData.count > 0 else { return }
        print("[Loki] Contact sync message received.")
        handleContactSyncMessageData(contactsAsData, using: transaction)
    }

    public static func handleContactSyncMessageData(_ data: Data, using transaction: YapDatabaseReadWriteTransaction) {
        let parser = ContactParser(data: data)
        let hexEncodedPublicKeys = parser.parseHexEncodedPublicKeys()
        // Try to establish sessions
        for hexEncodedPublicKey in hexEncodedPublicKeys {
            let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
            let friendRequestStatus = thread.friendRequestStatus
            switch friendRequestStatus {
            case .none:
                let messageSender = SSKEnvironment.shared.messageSender
                let autoGeneratedFRMessage = MultiDeviceProtocol.getAutoGeneratedMultiDeviceFRMessage(for: hexEncodedPublicKey, in: transaction)
                thread.isForceHidden = true
                thread.save(with: transaction)
                // This takes into account multi device
                messageSender.send(autoGeneratedFRMessage, success: {
                    DispatchQueue.main.async {
                        storage.dbReadWriteConnection.readWrite { transaction in
                            autoGeneratedFRMessage.remove(with: transaction)
                            thread.isForceHidden = false
                            thread.save(with: transaction)
                        }
                    }
                }, failure: { error in
                    DispatchQueue.main.async {
                        storage.dbReadWriteConnection.readWrite { transaction in
                            autoGeneratedFRMessage.remove(with: transaction)
                            thread.isForceHidden = false
                            thread.save(with: transaction)
                        }
                    }
                })
            case .requestReceived:
                thread.saveFriendRequestStatus(.friends, with: transaction)
                // Not sendFriendRequestAcceptanceMessage(to:in:using:) to take into account multi device
                FriendRequestProtocol.acceptFriendRequest(from: hexEncodedPublicKey, in: thread, using: transaction)
            default: break
            }
        }
    }

    @objc(handleClosedGroupSyncMessageIfNeeded:wrappedIn:using:)
    public static func handleClosedGroupSyncMessageIfNeeded(_ syncMessage: SSKProtoSyncMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (masterHexEncodedPublicKey == hexEncodedPublicKey)
        guard wasSentByMasterDevice, let groups = syncMessage.groups, let groupsAsData = groups.data, groupsAsData.count > 0 else { return }
        print("[Loki] Closed group sync message received.")
        let parser = ClosedGroupParser(data: groupsAsData)
        let groupModels = parser.parseGroupModels()
        for groupModel in groupModels {
            var thread: TSGroupThread! = TSGroupThread(groupId: groupModel.groupId, transaction: transaction)
            if thread == nil {
                thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)
                thread.save(with: transaction)
            }
            ClosedGroupsProtocol.establishSessionsIfNeeded(with: groupModel.groupMemberIds, in: thread, using: transaction)
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: "You have joined the group.")
            infoMessage.save(with: transaction)
        }
    }

    @objc(handleOpenGroupSyncMessageIfNeeded:wrappedIn:using:)
    public static func handleOpenGroupSyncMessageIfNeeded(_ syncMessage: SSKProtoSyncMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (masterHexEncodedPublicKey == hexEncodedPublicKey)
        guard wasSentByMasterDevice else { return }
        let groups = syncMessage.openGroups
        guard groups.count > 0 else { return }
        print("[Loki] Open group sync message received.")
        for openGroup in groups {
            LokiPublicChatManager.shared.addChat(server: openGroup.url, channel: openGroup.channel)
        }
    }
}
