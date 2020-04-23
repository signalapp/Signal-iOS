import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.

// TODO: Document the expected cases for everything and then express those cases in tests

public extension SessionProtocol {

    // When a message comes in, OWSMessageManager does things in this order:
    // 1. Checks if the message is a friend request from before restoration and ignores it if so
    // 2. Handles friend request acceptance if needed
    // 3. Checks if the message is a duplicate sync message and ignores it if so
    // 4. Handles pre keys if needed (this also might trigger a session reset)
    // 5. Updates P2P info if the message is a P2P address message
    // 6. Handle device linking requests or authorizations if needed (it now doesn't continue along the normal message handling path)
    // - If the message is a data message and has the session request flag set, processing stops here
    // - If the message is a data message and has the session restore flag set, processing stops here
    // 7. If the message got to this point, and it has an updated profile key attached, it'll now handle the profile key
    // - If the message is a closed group message, it'll now check if it needs to be ignored
    // ...

    /// Only ever modified from the message processing queue (`OWSBatchMessageProcessor.processingQueue`).
    private static var syncMessageTimestamps: [String:Set<UInt64>] = [:]

    @objc(isFriendRequestFromBeforeRestoration:)
    public static func isFriendRequestFromBeforeRestoration(_ envelope: SSKProtoEnvelope) -> Bool {
        // The envelope type is set during UD decryption
        let restorationTimeInMs = UInt64(storage.getRestorationTime() * 1000)
        return (envelope.type == .friendRequest && envelope.timestamp < restorationTimeInMs)
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

    // TODO: This seriously needs some explanation of when we expect pre key bundles to be attached
    @objc(handlePreKeyBundleMessageIfNeeded:wrappedIn:using:)
    public static func handlePreKeyBundleMessageIfNeeded(_ protoContent: SSKProtoContent, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let preKeyBundleMessage = protoContent.prekeyBundleMessage else { return }
        print("[Loki] Received a pre key bundle message from: \(hexEncodedPublicKey).")
        guard let preKeyBundle = preKeyBundleMessage.getPreKeyBundle(with: transaction) else {
            print("[Loki] Couldn't parse pre key bundle received from: \(hexEncodedPublicKey).")
            return
        }
        storage.setPreKeyBundle(preKeyBundle, forContact: hexEncodedPublicKey, transaction: transaction)
        // If we received a friend request (i.e. also a new pre key bundle), but we were already friends with the other user, reset the session
        // The envelope type is set during UD decryption
        if envelope.type == .friendRequest,
            let thread = TSContactThread.getWithContactId(hexEncodedPublicKey, transaction: transaction),
            thread.isContactFriend { // TODO: Maybe this should be getOrCreate?
            receiving_startSessionReset(in: thread, using: transaction)
            // Notify our other devices that we've started a session reset
            let syncManager = SSKEnvironment.shared.syncManager
            syncManager.syncContact(hexEncodedPublicKey, transaction: transaction)
        }
    }

    // TODO: Confusing that we have this but also the sending version
    @objc(receiving_startSessionResetInThread:using:)
    public static func receiving_startSessionReset(in thread: TSContactThread, using transaction: YapDatabaseReadWriteTransaction) {
        let hexEncodedPublicKey = thread.contactIdentifier()
        print("[Loki] Session reset request received from: \(hexEncodedPublicKey).")
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeLokiSessionResetInProgress)
        infoMessage.save(with: transaction)
        // Archive all sessions
        storage.archiveAllSessions(forContact: hexEncodedPublicKey, protocolContext: transaction)
        // Update session reset status
        thread.sessionResetStatus = .requestReceived
        thread.save(with: transaction)
        // Send an ephemeral message to trigger session reset for the other party as well
        let ephemeralMessage = EphemeralMessage(in: thread)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: ephemeralMessage, transaction: transaction)
    }

    @objc(handleP2PAddressMessageIfNeeded:wrappedIn:)
    public static func handleP2PAddressMessageIfNeeded(_ protoContent: SSKProtoContent, wrappedIn envelope: SSKProtoEnvelope) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let addressMessage = protoContent.lokiAddressMessage, let address = addressMessage.ptpAddress else { return }
        let portAsUInt32 = addressMessage.ptpPort
        guard portAsUInt32 != 0, portAsUInt32 < UInt16.max else { return }
        let port = UInt16(portAsUInt32)
        LokiP2PAPI.didReceiveLokiAddressMessage(forContact: hexEncodedPublicKey, address: address, port: port, receivedThroughP2P: envelope.isPtpMessage)
    }

    @objc(handleDeviceLinkMessageIfNeeded:wrappedIn:using:)
    public static func handleDeviceLinkMessageIfNeeded(_ protoContent: SSKProtoContent, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let deviceLinkMessage = protoContent.lokiDeviceLinkMessage, let master = deviceLinkMessage.masterHexEncodedPublicKey,
            let slave = deviceLinkMessage.slaveHexEncodedPublicKey, let slaveSignature = deviceLinkMessage.slaveSignature else {
            print("[Loki] Received an invalid device link message.")
            return
        }
        let deviceLinkingSession = DeviceLinkingSession.current
        if let masterSignature = deviceLinkMessage.masterSignature { // Authorization
            print("[Loki] Received a device link authorization from: \(hexEncodedPublicKey).") // Intentionally not `master`
            if let deviceLinkingSession = deviceLinkingSession {
                deviceLinkingSession.processLinkingAuthorization(from: master, for: slave, masterSignature: masterSignature, slaveSignature: slaveSignature)
            } else {
                print("[Loki] Received a device link authorization without a session; ignoring.")
            }
            // Set any profile info (the device link authorization also includes the master device's profile info)
            if let dataMessage = protoContent.dataMessage {
                updateDisplayNameIfNeeded(for: master, using: dataMessage, appendingShortID: false, in: transaction)
                updateProfileKeyIfNeeded(for: master, using: dataMessage)
            }
        } else { // Request
            print("[Loki] Received a device link request from: \(hexEncodedPublicKey).") // Intentionally not `slave`
            if let deviceLinkingSession = deviceLinkingSession {
                deviceLinkingSession.processLinkingRequest(from: slave, to: master, with: slaveSignature)
            } else {
                NotificationCenter.default.post(name: .unexpectedDeviceLinkRequestReceived, object: nil)
            }
        }
    }

    @objc(isSessionRequestMessage:)
    public static func isSessionRequestMessage(_ dataMessage: SSKProtoDataMessage) -> Bool {
        let sessionRequestFlag = SSKProtoDataMessage.SSKProtoDataMessageFlags.sessionRequest
        return dataMessage.flags & UInt32(sessionRequestFlag.rawValue) != 0
    }

    @objc(isSessionRestoreMessage:)
    public static func isSessionRestoreMessage(_ dataMessage: SSKProtoDataMessage) -> Bool {
        let sessionRestoreFlag = SSKProtoDataMessage.SSKProtoDataMessageFlags.sessionRestore
        return dataMessage.flags & UInt32(sessionRestoreFlag.rawValue) != 0
    }

    @objc(isUnlinkDeviceMessage:)
    public static func isUnlinkDeviceMessage(_ dataMessage: SSKProtoDataMessage) -> Bool {
        let unlinkDeviceFlag = SSKProtoDataMessage.SSKProtoDataMessageFlags.unlinkDevice
        return dataMessage.flags & UInt32(unlinkDeviceFlag.rawValue) != 0
    }

    @objc(shouldIgnoreClosedGroupMessage:inThread:wrappedIn:using:)
    public static func shouldIgnoreClosedGroupMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSThread, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadTransaction) -> Bool {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup,
            dataMessage.group?.type == .deliver else { return false }
        return thread.isUser(inGroup: hexEncodedPublicKey, transaction: transaction)
    }

    @objc(isValidSyncMessage:in:)
    public static func isValidSyncMessage(_ envelope: SSKProtoEnvelope, in transaction: YapDatabaseReadTransaction) -> Bool {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        let linkedDeviceHexEncodedPublicKeys = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        return linkedDeviceHexEncodedPublicKeys.contains(hexEncodedPublicKey)
    }

    @objc(updateProfileFromSyncMessageIfNeeded:wrappedIn:using:)
    public static func updateProfileFromSyncMessageIfNeeded(_ dataMessage: SSKProtoDataMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (masterHexEncodedPublicKey == hexEncodedPublicKey)
        guard wasSentByMasterDevice else { return }
        updateDisplayNameIfNeeded(for: masterHexEncodedPublicKey, using: dataMessage, appendingShortID: false, in: transaction)
        updateProfileKeyIfNeeded(for: masterHexEncodedPublicKey, using: dataMessage)
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
        establishSessionsIfNeeded(with: members, in: newGroupThread, using: transaction)
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
        let parser = ContactParser(data: contactsAsData)
        let hexEncodedPublicKeys = parser.parseHexEncodedPublicKeys()
        // Try to establish sessions
        for hexEncodedPublicKey in hexEncodedPublicKeys {
            let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
            let friendRequestStatus = thread.friendRequestStatus
            switch friendRequestStatus {
            case .none:
                let messageSender = SSKEnvironment.shared.messageSender
                let autoGeneratedFRMessage = getAutoGeneratedMultiDeviceFRMessage(for: hexEncodedPublicKey, in: transaction)
                thread.isForceHidden = true
                thread.save(with: transaction)
                messageSender.send(autoGeneratedFRMessage, success: {
                    storage.dbReadWriteConnection.readWrite { transaction in
                        autoGeneratedFRMessage.remove()
                        thread.isForceHidden = false
                    }
                }, failure: { error in
                    storage.dbReadWriteConnection.readWrite { transaction in
                        autoGeneratedFRMessage.remove()
                        thread.isForceHidden = false
                    }
                })
            case .requestReceived:
                thread.saveFriendRequestStatus(.friends, with: transaction)
                sendFriendRequestAcceptanceMessage(to: hexEncodedPublicKey, in: thread, using: transaction) // TODO: Shouldn't this be acceptFriendRequest so it takes into account multi device?
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
        let parser = GroupParser(data: groupsAsData)
        let groupModels = parser.parseGroupModels()
        for groupModel in groupModels {
            var thread: TSGroupThread! = TSGroupThread(groupId: groupModel.groupId, transaction: transaction)
            if thread == nil {
                thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)
                thread.save(with: transaction)
                establishSessionsIfNeeded(with: groupModel.groupMemberIds, in: thread, using: transaction)
                let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate, customMessage: "You have joined the group.")
                infoMessage.save(with: transaction)
            }
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

    @objc(handleUnlinkDeviceMessage:wrappedIn:using:)
    public static func handleUnlinkDeviceMessage(_ dataMessage: SSKProtoDataMessage, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: getUserHexEncodedPublicKey(), in: transaction) else { return }
        let wasSentByMasterDevice = (masterHexEncodedPublicKey == hexEncodedPublicKey)
        guard wasSentByMasterDevice else { return }
        let deviceLinks = storage.getDeviceLinks(for: hexEncodedPublicKey, in: transaction)
        if !deviceLinks.contains(where: { $0.master.hexEncodedPublicKey == hexEncodedPublicKey && $0.slave.hexEncodedPublicKey == getUserHexEncodedPublicKey() }) {
            return
        }
        LokiFileServerAPI.getDeviceLinks(associatedWith: getUserHexEncodedPublicKey(), in: transaction).done(on: .main) { deviceLinks in
            if deviceLinks.contains(where: { $0.master.hexEncodedPublicKey == hexEncodedPublicKey && $0.slave.hexEncodedPublicKey == getUserHexEncodedPublicKey() }) {
                UserDefaults.standard[.wasUnlinked] = true
                NotificationCenter.default.post(name: .dataNukeRequested, object: nil)
            }
        }
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:in:using:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ envelope: SSKProtoEnvelope, in thread: TSGroupThread?, using transaction: YapDatabaseReadTransaction) -> Bool {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let thread = thread else  { return false }
        return !thread.isUserAdmin(inGroup: hexEncodedPublicKey, transaction: transaction) // TODO: I wonder how this was happening in the first place?
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:in:using:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], in thread: TSGroupThread, using transaction: YapDatabaseReadWriteTransaction) {
        for member in closedGroupMembers {
            guard member != getUserHexEncodedPublicKey() else { continue }
            let hasSession = storage.containsSession(member, deviceId: 1, protocolContext: transaction) // TODO: Instead of 1 we should use the primary device ID thingy
            if hasSession { continue }
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            let sessionRequestMessage = LKSessionRequestMessage(thread: thread)
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
            messageSenderJobQueue.add(message: sessionRequestMessage, transaction: transaction)
        }
    }

    @objc(updateDisplayNameIfNeededForHexEncodedPublicKey:using:appendingShortID:in:)
    public static func updateDisplayNameIfNeeded(for hexEncodedPublicKey: String, using dataMessage: SSKProtoDataMessage, appendingShortID appendShortID: Bool, in transaction: YapDatabaseReadWriteTransaction) {
        guard let profile = dataMessage.profile, let rawDisplayName = profile.displayName else { return }
        let displayName: String
        if appendShortID {
            let shortID = hexEncodedPublicKey.substring(from: hexEncodedPublicKey.index(hexEncodedPublicKey.endIndex, offsetBy: -8))
            displayName = "\(rawDisplayName) (...\(shortID))"
        } else {
            displayName = rawDisplayName
        }
        let profileManager = SSKEnvironment.shared.profileManager
        profileManager.updateProfileForContact(withID: hexEncodedPublicKey, displayName: displayName, with: transaction)
    }

    @objc(updateProfileKeyIfNeededForHexEncodedPublicKey:using:)
    public static func updateProfileKeyIfNeeded(for hexEncodedPublicKey: String, using dataMessage: SSKProtoDataMessage) {
        guard dataMessage.hasProfileKey, let profileKey = dataMessage.profileKey else { return }
        let profilePictureURL = dataMessage.profile?.profilePicture
        guard profileKey.count == kAES256_KeyByteLength else {
            print("[Loki] Unexpected profile key size: \(profileKey.count).")
            return
        }
        let profileManager = SSKEnvironment.shared.profileManager
        // This dispatches async on the main queue internally, where it starts a new write transaction. Apparently that's an okay thing to do in this case?
        profileManager.setProfileKeyData(profileKey, forRecipientId: hexEncodedPublicKey, avatarURL: profilePictureURL)
    }

    @objc(canFriendRequestBeAutoAcceptedForHexEncodedPublicKey:in:using:)
    public static func canFriendRequestBeAutoAccepted(for hexEncodedPublicKey: String, in thread: TSThread, using transaction: YapDatabaseReadTransaction) -> Bool {
        if thread.hasCurrentUserSentFriendRequest {
            // This can happen if Alice sent Bob a friend request, Bob declined, but then Bob changed his
            // mind and sent a friend request to Alice. In this case we want Alice to auto-accept the request
            // and send a friend request accepted message back to Bob. We don't check that sending the
            // friend request accepted message succeeded. Even if it doesn't, the thread's current friend
            // request status will be set to LKThreadFriendRequestStatusFriends for Alice making it possible
            // for Alice to send messages to Bob. When Bob receives a message, his thread's friend request status
            // will then be set to LKThreadFriendRequestStatusFriends. If we do check for a successful send
            // before updating Alice's thread's friend request status to LKThreadFriendRequestStatusFriends,
            // we can end up in a deadlock where both users' threads' friend request statuses are
            // LKThreadFriendRequestStatusRequestSent.
            return true
        }
        // Auto-accept any friend requests from the user's own linked devices
        let userLinkedDeviceHexEncodedPublicKeys = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        if userLinkedDeviceHexEncodedPublicKeys.contains(hexEncodedPublicKey) { return true }
        // Auto-accept if the user is friends with any of the sender's linked devices.
        let senderLinkedDeviceThreads = LokiDatabaseUtilities.getLinkedDeviceThreads(for: hexEncodedPublicKey, in: transaction)
        if senderLinkedDeviceThreads.contains(where: { $0.isContactFriend }) { return true }
        // We can't auto-accept
        return false
    }

    @objc(handleFriendRequestAcceptanceIfNeeded:in:)
    public static func handleFriendRequestAcceptanceIfNeeded(_ envelope: SSKProtoEnvelope, in transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        // The envelope type is set during UD decryption.
        guard !envelope.isGroupChatMessage && envelope.type != .friendRequest else { return }
        // If we get an envelope that isn't a friend request, then we can infer that we had to use
        // Signal cipher decryption and thus that we have a session with the other person.
        let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
        // We shouldn't be able to skip from none to friends
        guard thread.friendRequestStatus != .none else { return }
        // Become friends
        thread.saveFriendRequestStatus(.friends, with: transaction)
        if let existingFriendRequestMessage = thread.getLastInteraction(with: transaction) as? TSOutgoingMessage,
            existingFriendRequestMessage.isFriendRequest {
            existingFriendRequestMessage.saveFriendRequestStatus(.accepted, with: transaction)
        }
        // Send our P2P details
        if let addressMessage = LokiP2PAPI.onlineBroadcastMessage(forThread: thread) {
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
            messageSenderJobQueue.add(message: addressMessage, transaction: transaction)
        }
    }

    @objc(handleFriendRequestMessageIfNeeded:associatedWith:wrappedIn:in:using:)
    public static func handleFriendRequestMessageIfNeeded(_ dataMessage: SSKProtoDataMessage, associatedWith message: TSIncomingMessage, wrappedIn envelope: SSKProtoEnvelope, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        guard !envelope.isGroupChatMessage else {
            print("[Loki] Ignoring friend request in group chat.")
            return
        }
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        // The envelope type is set during UD decryption.
        guard envelope.type == .friendRequest else {
            print("[Loki] Ignoring friend request logic for non friend request type envelope.")
            return
        }
        if canFriendRequestBeAutoAccepted(for: hexEncodedPublicKey, in: thread, using: transaction) {
            thread.saveFriendRequestStatus(.friends, with: transaction)
            var existingFriendRequestMessage: TSOutgoingMessage?
            thread.enumerateInteractions(with: transaction) { interaction, _ in
                if let outgoingMessage = interaction as? TSOutgoingMessage, outgoingMessage.isFriendRequest {
                    existingFriendRequestMessage = outgoingMessage
                }
            }
            if let existingFriendRequestMessage = existingFriendRequestMessage {
                existingFriendRequestMessage.saveFriendRequestStatus(.accepted, with: transaction)
            }
            sendFriendRequestAcceptanceMessage(to: hexEncodedPublicKey, in: thread, using: transaction)
        } else if !thread.isContactFriend {
            // Checking that the sender of the message isn't already a friend is necessary because otherwise
            // the following situation can occur: Alice and Bob are friends. Bob loses his database and his
            // friend request status is reset to LKThreadFriendRequestStatusNone. Bob now sends Alice a friend
            // request. Alice's thread's friend request status is reset to
            // LKThreadFriendRequestStatusRequestReceived.
            thread.saveFriendRequestStatus(.requestReceived, with: transaction)
            // Except for the message.friendRequestStatus = LKMessageFriendRequestStatusPending line below, all of this is to ensure that
            // there's only ever one message with status LKMessageFriendRequestStatusPending in a thread (where a thread is the combination
            // of all threads belonging to the linked devices of a user).
            let linkedDeviceThreads = LokiDatabaseUtilities.getLinkedDeviceThreads(for: hexEncodedPublicKey, in: transaction)
            for thread in linkedDeviceThreads {
                thread.enumerateInteractions(with: transaction) { interaction, _ in
                    guard let incomingMessage = interaction as? TSIncomingMessage,
                        incomingMessage.friendRequestStatus != .none else { return }
                    incomingMessage.saveFriendRequestStatus(.none, with: transaction)
                }
            }
            message.friendRequestStatus = .pending
            // Don't save yet. This is done in finalizeIncomingMessage:thread:masterThread:envelope:transaction.
        }
    }
}
