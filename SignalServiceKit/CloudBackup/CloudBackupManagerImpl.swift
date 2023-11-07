//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class NotImplementedError: Error {}

public class CloudBackupManagerImpl: CloudBackupManager {

    private let blockingManager: CloudBackup.Shims.BlockingManager
    private let dateProvider: DateProvider
    private let db: DB
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let profileManager: CloudBackup.Shims.ProfileManager
    private let recipientHidingManager: RecipientHidingManager
    private let signalRecipientFetcher: CloudBackup.Shims.SignalRecipientFetcher
    private let storyFinder: CloudBackup.Shims.StoryFinder
    private let streamProvider: CloudBackupOutputStreamProvider
    private let tsAccountManager: TSAccountManager
    private let tsInteractionFetcher: CloudBackup.Shims.TSInteractionFetcher
    private let tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher

    public init(
        blockingManager: CloudBackup.Shims.BlockingManager,
        dateProvider: @escaping DateProvider,
        db: DB,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        profileManager: CloudBackup.Shims.ProfileManager,
        recipientHidingManager: RecipientHidingManager,
        signalRecipientFetcher: CloudBackup.Shims.SignalRecipientFetcher,
        storyFinder: CloudBackup.Shims.StoryFinder,
        streamProvider: CloudBackupOutputStreamProvider,
        tsAccountManager: TSAccountManager,
        tsInteractionFetcher: CloudBackup.Shims.TSInteractionFetcher,
        tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher
    ) {
        self.blockingManager = blockingManager
        self.dateProvider = dateProvider
        self.db = db
        self.dmConfigurationStore = dmConfigurationStore
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.recipientHidingManager = recipientHidingManager
        self.signalRecipientFetcher = signalRecipientFetcher
        self.storyFinder = storyFinder
        self.streamProvider = streamProvider
        self.tsAccountManager = tsAccountManager
        self.tsInteractionFetcher = tsInteractionFetcher
        self.tsThreadFetcher = tsThreadFetcher
    }

    public func createBackup() async throws -> URL {
        guard FeatureFlags.cloudBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        return try await db.awaitableWrite { tx in
            // The mother of all write transactions. Eventually we want to use
            // a read tx, and use explicit locking to prevent other things from
            // happening in the meantime (e.g. message processing) but for now
            // hold the single write lock and call it a day.
            return try self._createBackup(tx: tx)
        }
    }

    public func importBackup(fileUrl: URL) async throws {
        guard FeatureFlags.cloudBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        try await db.awaitableWrite { tx in
            // This has to open one big write transaction; the alternative is
            // to chunk them into separate writes. Nothing else should be happening
            // in the app anyway.
            do {
                try self._importBackup(fileUrl, tx: tx)
            } catch let error {
                owsFailDebug("Failed! \(error)")
                throw error
            }
        }
    }

    private func _createBackup(tx: DBWriteTransaction) throws -> URL {
        let stream: CloudBackupOutputStream
        switch streamProvider.openOutputFileStream() {
        case .success(let streamResult):
            stream = streamResult
        case .failure(let error):
            throw error
        }

        try writeHeader(stream: stream, tx: tx)

        let (nextRecipientProtoId, addressMap) = try writeRecipients(stream: stream, tx: tx)
        let groupIdMap = try writeGroups(nextRecipientProtoId: nextRecipientProtoId, stream: stream, tx: tx)
        let chatIdMap = try writeThreads(addressMap: addressMap, groupIdMap: groupIdMap, stream: stream, tx: tx)
        try writeMessages(chatMap: chatIdMap, addressMap: addressMap, stream: stream, tx: tx)

        return stream.closeFileStream()
    }

    private func writeHeader(stream: CloudBackupOutputStream, tx: DBWriteTransaction) throws {
        let backupInfo = try BackupProtoBackupInfo.builder(
            version: 1,
            backupTime: dateProvider().ows_millisecondsSince1970
        ).build()
        try stream.writeHeader(backupInfo)
    }

    private func writeRecipients(
        stream: CloudBackupOutputStream,
        tx: DBReadTransaction
    ) throws -> (UInt64, [SignalServiceAddress: UInt64]) {
        var currentRecipientProtoId: UInt64 = 1
        var addressMap = [SignalServiceAddress: UInt64]()

        let whitelistedAddresses = Set(profileManager.allWhitelistedRegisteredAddresses(tx: tx))
        let blockedAddresses = blockingManager.blockedAddresses(tx: tx)

        var firstError: Error?

        guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
            throw OWSAssertionError("No local address!")
        }
        // Write the local recipient first.
        let selfBuilder = BackupProtoSelfRecipient.builder()
        let selfProto = try selfBuilder.build()
        let selfRecipientBuilder = BackupProtoRecipient.builder(id: currentRecipientProtoId)
        addressMap[localAddress] = currentRecipientProtoId
        currentRecipientProtoId += 1
        selfRecipientBuilder.setSelfRecipient(selfProto)
        let selfRecipientProto = try selfRecipientBuilder.build()
        let selfFrameBuilder = BackupProtoFrame.builder()
        selfFrameBuilder.setRecipient(selfRecipientProto)
        let selfFrame = try selfFrameBuilder.build()
        try stream.writeFrame(selfFrame)

        signalRecipientFetcher.enumerateAll(tx: tx) { recipient in
            do {
                let recipientAddress = recipient.address

                let recipientBuilder = BackupProtoRecipient.builder(
                    id: currentRecipientProtoId
                )
                addressMap[recipient.address] = currentRecipientProtoId
                currentRecipientProtoId += 1

                var unregisteredAtTimestamp: UInt64 = 0
                if !recipient.isRegistered {
                    unregisteredAtTimestamp = (
                        recipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp
                    )
                }

                // TODO: instead of doing per-recipient fetches, we should bulk load
                // some of these fetched fields into memory to avoid db round trips.
                let contactBuilder = BackupProtoContact.builder(
                    blocked: blockedAddresses.contains(recipientAddress),
                    hidden: self.recipientHidingManager.isHiddenRecipient(recipient, tx: tx),
                    unregisteredTimestamp: unregisteredAtTimestamp,
                    profileSharing: whitelistedAddresses.contains(recipient.address),
                    hideStory: recipient.aci.map { self.storyFinder.isStoryHidden(forAci: $0, tx: tx) ?? false } ?? false
                )

                contactBuilder.setRegistered(recipient.isRegistered ? .registered : .notRegistered)

                recipient.aci.map(\.rawUUID.data).map(contactBuilder.setAci)
                recipient.pni.map(\.rawUUID.data).map(contactBuilder.setPni)
                recipient.address.e164.map(\.uint64Value).map(contactBuilder.setE164)
                // TODO: username?

                let profile = self.profileManager.getUserProfile(for: recipientAddress, tx: tx)
                profile?.profileKey.map(\.keyData).map(contactBuilder.setProfileKey(_:))
                profile?.unfilteredGivenName.map(contactBuilder.setProfileGivenName(_:))
                profile?.unfilteredFamilyName.map(contactBuilder.setProfileFamilyName(_:))
                // TODO: joined name?

                let contact = try contactBuilder.build()
                recipientBuilder.setContact(contact)
                let protoRecipient = try recipientBuilder.build()
                let frameBuilder = BackupProtoFrame.builder()
                frameBuilder.setRecipient(protoRecipient)
                let frame = try frameBuilder.build()
                try stream.writeFrame(frame)
            } catch let error {
                owsFailDebug("Failed to write recipient!")
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }

        return (currentRecipientProtoId, addressMap)
    }

    private func writeGroups(
        nextRecipientProtoId: UInt64,
        stream: CloudBackupOutputStream,
        tx: DBReadTransaction
    ) throws -> [Data: UInt64] {
        var currentRecipientProtoId = nextRecipientProtoId
        var idMap = [Data: UInt64]()

        var firstError: Error?

        try tsThreadFetcher.enumerateAllGroupThreads(tx: tx) { groupThread in
            do {
                guard groupThread.isGroupV2Thread, let groupsV2Model = groupThread.groupModel as? TSGroupModelV2 else {
                    return
                }
                let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupsV2Model.secretParamsData))
                let groupMasterKey = try groupSecretParams.getMasterKey().serialize().asData

                // TODO: instead of doing per-thread fetches, we should bulk load
                // some of these fetched fields into memory to avoid db round trips.
                let groupBuilder = BackupProtoGroup.builder(
                    masterKey: groupMasterKey,
                    whitelisted: self.profileManager.isThread(inProfileWhitelist: groupThread, tx: tx),
                    hideStory: self.storyFinder.isStoryHidden(forGroupThread: groupThread, tx: tx) ?? false
                )
                switch groupThread.storyViewMode {
                case .disabled:
                    groupBuilder.setStorySendMode(.disabled)
                case .explicit:
                    groupBuilder.setStorySendMode(.enabled)
                default:
                    groupBuilder.setStorySendMode(.default)
                }

                let groupProto = try groupBuilder.build()
                let recipientBuilder = BackupProtoRecipient.builder(
                    id: currentRecipientProtoId
                )
                idMap[groupThread.groupId] = currentRecipientProtoId
                currentRecipientProtoId += 1

                recipientBuilder.setGroup(groupProto)

                let recipientProto = try recipientBuilder.build()

                let frameBuilder = BackupProtoFrame.builder()
                frameBuilder.setRecipient(recipientProto)
                let frame = try frameBuilder.build()

                try stream.writeFrame(frame)

            } catch let error {
                owsFailDebug("Failed to write recipient!")
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }

        return idMap
    }

    private func writeThreads(
        addressMap: [SignalServiceAddress: UInt64],
        groupIdMap: [Data: UInt64],
        stream: CloudBackupOutputStream,
        tx: DBReadTransaction
    ) throws -> [String: UInt64] {
        var currentChatId: UInt64 = 1
        var idMap = [String: UInt64]()

        var firstError: Error?

        tsThreadFetcher.enumerateAll(tx: tx) { thread in
            do {
                guard thread is TSGroupThread || thread is TSContactThread else {
                    return
                }

                let recipientProtoId: UInt64
                if
                    let groupId = (thread as? TSGroupThread)?.groupId,
                    let id = groupIdMap[groupId]
                {
                    recipientProtoId = id
                } else if
                    let contactAddress = (thread as? TSContactThread)?.contactAddress,
                    let id = addressMap[contactAddress]
                {
                    recipientProtoId = id
                } else {
                    owsFailDebug("Missing proto recipient id!")
                    return
                }

                let threadAssociatedData = self.tsThreadFetcher.fetchOrDefaultThreadAssociatedData(for: thread, tx: tx)

                let chatBuilder = BackupProtoChat.builder(
                    id: currentChatId,
                    recipientID: recipientProtoId,
                    archived: threadAssociatedData.isArchived,
                    pinned: self.tsThreadFetcher.isThreadPinned(thread),
                    // TODO: should this be millis? or seconds?
                    expirationTimer: UInt64(self.dmConfigurationStore.durationSeconds(for: thread, tx: tx)),
                    muteUntil: threadAssociatedData.mutedUntilTimestamp,
                    markedUnread: threadAssociatedData.isMarkedUnread,
                    // TODO: this is commented out on storageService? ignoring for now.
                    dontNotifyForMentionsIfMuted: false
                )
                idMap[thread.uniqueId] = currentChatId
                currentChatId += 1

                let chatProto = try chatBuilder.build()
                let frameBuilder = BackupProtoFrame.builder()
                frameBuilder.setChat(chatProto)
                let frame = try frameBuilder.build()

                try stream.writeFrame(frame)

            } catch let error {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }

        return idMap
    }

    private func writeMessages(
        chatMap: [String: UInt64],
        addressMap: [SignalServiceAddress: UInt64],
        stream: CloudBackupOutputStream,
        tx: DBReadTransaction
    ) throws {
        guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
            owsFailDebug("No local address!")
            return
        }

        var firstError: Error?

        tsInteractionFetcher.enumerateAllTextOnlyMessages(tx: tx) { message in
            do {
                if message.wasRemotelyDeleted {
                    // TODO: handle remotely deleted messages
                    return
                }
                guard let chatId = chatMap[message.uniqueThreadId] else {
                    owsFailDebug("Message missing chat")
                    return
                }
                let authorAddress = (message as? TSIncomingMessage)?.authorAddress ?? localAddress
                guard let authorId = addressMap[authorAddress] else {
                    owsFailDebug("missing author id!")
                    return
                }

                let chatItemBuilder = BackupProtoChatItem.builder(
                    chatID: chatId,
                    authorID: authorId,
                    dateSent: message.timestamp,
                    dateReceived: message.receivedAtTimestamp,
                    sms: false
                )
                // TODO: don't include messages expiring within 24hr
                if message.expireStartedAt > 0 {
                    chatItemBuilder.setExpireStart(message.expireStartedAt)
                }
                if message.expiresAt > 0 {
                    chatItemBuilder.setExpiresIn(message.expiresAt)
                }
                switch message.editState {
                case .latestRevisionRead, .latestRevisionUnread, .none:
                    break
                case .pastRevision:
                    // TODO: include message edits
                    return
                }

                if let incomingMessage = message as? TSIncomingMessage {
                    let incomingMessageProtoBuilder = BackupProtoChatItemIncomingMessageDetails.builder(
                        dateServerSent: incomingMessage.serverDeliveryTimestamp,
                        read: incomingMessage.wasRead,
                        sealedSender: incomingMessage.wasReceivedByUD
                    )
                    let incomingMessageProto = try incomingMessageProtoBuilder.build()
                    chatItemBuilder.setIncoming(incomingMessageProto)
                } else if let outgoingMessage = message as? TSOutgoingMessage {
                    let outgoingMessageProtoBuilder = BackupProtoChatItemOutgoingMessageDetails.builder()

                    try outgoingMessage.recipientAddressStates?.keys.forEach { address in
                        guard let sendState = outgoingMessage.recipientState(for: address) else {
                            return
                        }
                        guard let recipientId = addressMap[address] else {
                            owsFailDebug("Missing recipient for message!")
                            return
                        }
                        var isNetworkFailure = false
                        var isIdentityKeyMismatchFailure = false
                        let protoDeliveryStatus: BackupProtoSendStatusStatus
                        let statusTimestamp: UInt64
                        switch sendState.state {
                        case OWSOutgoingMessageRecipientState.sent:
                            if let readTimestamp = sendState.readTimestamp {
                                protoDeliveryStatus = .read
                                statusTimestamp = readTimestamp.uint64Value
                            } else if let viewedTimestamp = sendState.viewedTimestamp {
                                protoDeliveryStatus = .viewed
                                statusTimestamp = viewedTimestamp.uint64Value
                            } else if let deliveryTimestamp = sendState.deliveryTimestamp {
                                protoDeliveryStatus = .delivered
                                statusTimestamp = deliveryTimestamp.uint64Value
                            } else {
                                protoDeliveryStatus = .sent
                                statusTimestamp = message.timestamp
                            }
                        case OWSOutgoingMessageRecipientState.failed:
                            // TODO: identify specific errors. for now call everything network.
                            isNetworkFailure = true
                            isIdentityKeyMismatchFailure = false
                            protoDeliveryStatus = .failed
                            statusTimestamp = message.timestamp
                        case OWSOutgoingMessageRecipientState.sending, OWSOutgoingMessageRecipientState.pending:
                            protoDeliveryStatus = .pending
                            statusTimestamp = message.timestamp
                        case OWSOutgoingMessageRecipientState.skipped:
                            protoDeliveryStatus = .skipped
                            statusTimestamp = message.timestamp
                        }

                        let sendStatusBuilder: BackupProtoSendStatusBuilder = BackupProtoSendStatus.builder(
                            recipientID: recipientId,
                            networkFailure: isNetworkFailure,
                            identityKeyMismatch: isIdentityKeyMismatchFailure,
                            sealedSender: sendState.wasSentByUD.negated,
                            timestamp: statusTimestamp
                        )
                        sendStatusBuilder.setDeliveryStatus(protoDeliveryStatus)
                        let sendStatus = try sendStatusBuilder.build()
                        outgoingMessageProtoBuilder.addSendStatus(sendStatus)
                    }

                    let outgoingMessageProto = try outgoingMessageProtoBuilder.build()
                    chatItemBuilder.setOutgoing(outgoingMessageProto)
                }

                guard let body = message.body else {
                    // TODO: handle non simple text messages.
                    return
                }

                let standardMessageBuilder = BackupProtoStandardMessage.builder()
                let textBuilder = BackupProtoText.builder(body: body)
                for bodyRange in message.bodyRanges?.toProtoBodyRanges() ?? [] {
                    let bodyRangeProtoBuilder = BackupProtoBodyRange.builder()
                    bodyRangeProtoBuilder.setStart(bodyRange.start)
                    bodyRangeProtoBuilder.setLength(bodyRange.length)
                    if let mentionAci = bodyRange.mentionAci {
                        bodyRangeProtoBuilder.setMentionAci(mentionAci)
                    } else if let style = bodyRange.style {
                        switch style {
                        case .none:
                            bodyRangeProtoBuilder.setStyle(.none)
                        case .bold:
                            bodyRangeProtoBuilder.setStyle(.bold)
                        case .italic:
                            bodyRangeProtoBuilder.setStyle(.italic)
                        case .spoiler:
                            bodyRangeProtoBuilder.setStyle(.spoiler)
                        case .strikethrough:
                            bodyRangeProtoBuilder.setStyle(.strikethrough)
                        case .monospace:
                            bodyRangeProtoBuilder.setStyle(.monospace)
                        }
                    }
                    let bodyRangeProto = try bodyRangeProtoBuilder.build()
                    textBuilder.addBodyRanges(bodyRangeProto)
                }
                let textProto = try textBuilder.build()
                standardMessageBuilder.setText(textProto)

                // TODO: reactions

                let standardMessageProto = try standardMessageBuilder.build()
                chatItemBuilder.setStandardMessage(standardMessageProto)
                let chatItemProto = try chatItemBuilder.build()
                let frameBuilder = BackupProtoFrame.builder()
                frameBuilder.setChatItem(chatItemProto)
                let frame = try frameBuilder.build()
                try stream.writeFrame(frame)

            } catch let error {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func _importBackup(_ fileUrl: URL, tx: DBWriteTransaction) throws {
        let stream: CloudBackupInputStream
        switch streamProvider.openInputFileStream(fileURL: fileUrl) {
        case .success(let streamResult):
            stream = streamResult
        case .failure(let error):
            throw error
        }

        defer {
            stream.closeFileStream()
        }

        let header = try stream.readHeader()
        guard let backupInfo = header.object else {
            return
        }

        Logger.info("Reading backup with version: \(backupInfo.version) backed up at \(backupInfo.backupTime)")

        var aciMap = [UInt64: Aci]()
        var pniMap = [UInt64: Pni]()
        var addressMap = [UInt64: SignalServiceAddress]()
        var groupIdMap = [UInt64: Data]()
        var threadUniqueIdMap = [UInt64: String]()

        var hasMoreFrames = header.moreBytesAvailable
        while hasMoreFrames {
            let frame = try stream.readFrame()
            hasMoreFrames = frame.moreBytesAvailable
            if let recipient = frame.object?.recipient {
                if let contact = recipient.contact {
                    try handleReadContact(
                        contact,
                        recipientProtoId: recipient.id,
                        aciMap: &aciMap,
                        pniMap: &pniMap,
                        addressMap: &addressMap,
                        tx: tx
                    )
                } else if let group = recipient.group {
                    try handleReadGroup(
                        group,
                        recipientProtoId: recipient.id,
                        groupIdMap: &groupIdMap,
                        tx: tx
                    )
                }
            } else if let chat = frame.object?.chat {
                try handleReadChat(
                    chat,
                    addressMap: addressMap,
                    groupIdMap: groupIdMap,
                    threadUniqueIdMap: &threadUniqueIdMap,
                    tx: tx
                )
            } else if let chatItem = frame.object?.chatItem {
                try handleReadChatItem(
                    chatItem: chatItem,
                    aciMap: aciMap,
                    pniMap: pniMap,
                    threadUniqueIdMap: threadUniqueIdMap,
                    tx: tx
                )
            }
        }

        return stream.closeFileStream()
    }

    private func handleReadContact(
        _ contactProto: BackupProtoContact,
        recipientProtoId: UInt64,
        aciMap: inout [UInt64: Aci],
        pniMap: inout [UInt64: Pni],
        addressMap: inout [UInt64: SignalServiceAddress],
        tx: DBWriteTransaction
    ) throws {
        let isRegistered: Bool?
        let unregisteredTimestamp: UInt64?
        switch contactProto.registered {
        case .none, .unknown:
            isRegistered = nil
            unregisteredTimestamp = nil
        case .registered:
            isRegistered = true
            unregisteredTimestamp = nil
        case .notRegistered:
            isRegistered = false
            unregisteredTimestamp = contactProto.unregisteredTimestamp
        }

        let aci: Aci? = contactProto.aci.map(UUID.from(data:))?.map(\.0).map(Aci.init(fromUUID:))
        let pni: Pni? = contactProto.pni.map(UUID.from(data:))?.map(\.0).map(Pni.init(fromUUID:))
        if let aci {
            aciMap[recipientProtoId] = aci
        }
        if let pni {
            pniMap[recipientProtoId] = pni
        }

        var recipient = SignalRecipient.proofOfConcept_forBackup(
            aci: aci,
            pni: pni,
            phoneNumber: E164(contactProto.e164),
            isRegistered: isRegistered,
            unregisteredAtTimestamp: unregisteredTimestamp
        )

        // This is bad, but needed because the import can happen at any time
        // and we don't wipe the db. in the future, we will only do this restore
        // during registration/linking, with an empty database.
        if let existingRecipient = signalRecipientFetcher.recipient(for: recipient.address, tx: tx) {
            recipient = existingRecipient
            if isRegistered == true, !recipient.isRegistered {
                signalRecipientFetcher.markAsRegisteredAndSave(recipient, tx: tx)
            } else if isRegistered == false, recipient.isRegistered, let unregisteredTimestamp {
                signalRecipientFetcher.markAsUnregisteredAndSave(recipient, at: unregisteredTimestamp, tx: tx)
            }
        } else {
            try signalRecipientFetcher.insert(recipient, tx: tx)
        }

        addressMap[recipientProtoId] = recipient.address

        if contactProto.profileSharing {
            // Add to the whitelist.
            profileManager.addToWhitelist(recipient.address, tx: tx)
        }

        if contactProto.blocked {
            blockingManager.addBlockedAddress(recipient.address, tx: tx)
        }

        if contactProto.hidden {
            try recipientHidingManager.addHiddenRecipient(recipient, wasLocallyInitiated: false, tx: tx)
        }

        if contactProto.hideStory, let aci {
            let storyContext = storyFinder.getOrCreateStoryContextAssociatedData(for: aci, tx: tx)
            storyFinder.setStoryContextHidden(storyContext, tx: tx)
        }

        profileManager.setProfileGivenName(
            givenName: contactProto.profileGivenName,
            familyName: contactProto.profileFamilyName,
            profileKey: contactProto.profileKey,
            address: recipient.address,
            tx: tx
        )
    }

    private func handleReadGroup(
        _ groupProto: BackupProtoGroup,
        recipientProtoId: UInt64,
        groupIdMap: inout [UInt64: Data],
        tx: DBWriteTransaction
    ) throws {
        let masterKey = groupProto.masterKey

        guard groupsV2.isValidGroupV2MasterKey(masterKey) else {
            owsFailDebug("Invalid master key.")
            return
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        } catch {
            owsFailDebug("Invalid master key.")
            return
        }
        let groupId = groupContextInfo.groupId

        var needsUpdate = false

        let groupThread: TSGroupThread

        if let localThread = tsThreadFetcher.fetch(groupId: groupId, tx: tx) {
            let localStorySendMode = localThread.storyViewMode.storageServiceMode
            switch (groupProto.storySendMode, localThread.storyViewMode) {
            case (.disabled, .disabled), (.enabled, .explicit), (.default, _), (nil, _):
                // Nothing to change.
                break
            case (.disabled, _):
                tsThreadFetcher.updateWithStorySendEnabled(false, groupThread: localThread, tx: tx)
            case (.enabled, _):
                tsThreadFetcher.updateWithStorySendEnabled(true, groupThread: localThread, tx: tx)
            }
            groupThread = localThread
        } else {
            // TODO: creating groups is async and scheduled in GroupsV2. Punt for now.
            return
        }

        groupIdMap[recipientProtoId] = groupId

        if groupProto.whitelisted {
            profileManager.addToWhitelist(groupThread, tx: tx)
        }

        if groupProto.hideStory {
            let storyContext = storyFinder.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: tx)
            storyFinder.setStoryContextHidden(storyContext, tx: tx)
        }
    }

    private func handleReadChat(
        _ chatProto: BackupProtoChat,
        addressMap: [UInt64: SignalServiceAddress],
        groupIdMap: [UInt64: Data],
        threadUniqueIdMap: inout [UInt64: String],
        tx: DBWriteTransaction
    ) throws {
        let thread: TSThread
        if let groupId = groupIdMap[chatProto.recipientID] {
            // We don't create the group thread here; that happened when parsing the Group.
            // Instead, just set metadata.
            guard let groupThread = tsThreadFetcher.fetch(groupId: groupId, tx: tx) else {
                return
            }
            thread = groupThread
        } else if let address = addressMap[chatProto.recipientID] {
            thread = tsThreadFetcher.getOrCreateContactThread(with: address, tx: tx)
        } else {
            owsFailDebug("Missing recipient for chat!")
            return
        }

        threadUniqueIdMap[chatProto.id] = thread.uniqueId

        var associatedDataNeedsUpdate = false
        var isArchived: Bool?
        var isMarkedUnread: Bool?
        var mutedUntilTimestamp: UInt64?

        // TODO: should probably unarchive if set to false?
        if chatProto.archived {
            associatedDataNeedsUpdate = true
            isArchived = true
        }
        if chatProto.markedUnread {
            associatedDataNeedsUpdate = true
            isMarkedUnread = true
        }
        if chatProto.muteUntil != 0 {
            associatedDataNeedsUpdate = true
            mutedUntilTimestamp = chatProto.muteUntil
        }

        if associatedDataNeedsUpdate {
            let threadAssociatedData = tsThreadFetcher.fetchOrDefaultThreadAssociatedData(for: thread, tx: tx)
            tsThreadFetcher.updateAssociatedData(
                threadAssociatedData,
                isArchived: isArchived,
                isMarkedUnread: isMarkedUnread,
                mutedUntilTimestamp: mutedUntilTimestamp,
                tx: tx
            )
        }
        if chatProto.pinned {
            do {
                try tsThreadFetcher.pinThread(thread, tx: tx)
            } catch {
                // TODO: we might pin a thread thats already pinned.
                // Ignore this error, but ideally catch others.
            }
        }

        if chatProto.expirationTimer != 0 {
            // TODO: should this be millis? or seconds?
            dmConfigurationStore.set(
                token: .init(isEnabled: true, durationSeconds: UInt32(chatProto.expirationTimer)),
                for: .thread(thread),
                tx: tx
            )
        }
    }

    private func handleReadChatItem(
        chatItem: BackupProtoChatItem,
        aciMap: [UInt64: Aci],
        pniMap: [UInt64: Pni],
        threadUniqueIdMap: [UInt64: String],
        tx: DBWriteTransaction
    ) throws {
        guard let standardMessage = chatItem.standardMessage else {
            // TODO: handle other message types
            return
        }

        guard
            let threadUniqueId = threadUniqueIdMap[chatItem.chatID],
            let thread = tsThreadFetcher.fetch(threadUniqueId: threadUniqueId, tx: tx)
        else {
            owsFailDebug("Missing thread for message!")
            return
        }

        let bodyRanges: MessageBodyRanges?
        if let bodyRangesProto = standardMessage.text?.bodyRanges, !bodyRangesProto.isEmpty {

            var bodyMentions = [NSRange: Aci]()
            var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
            for bodyRange in bodyRangesProto {
                let range = NSRange(location: Int(bodyRange.start), length: Int(bodyRange.length))
                if bodyRange.hasMentionAci, let mentionAci = Aci.parseFrom(aciString: bodyRange.mentionAci) {
                    bodyMentions[range] = mentionAci
                } else if bodyRange.hasStyle {
                    let swiftStyle: MessageBodyRanges.SingleStyle
                    switch bodyRange.style {
                    case .some(.none), nil:
                        continue
                    case .bold:
                        swiftStyle = .bold
                    case .italic:
                        swiftStyle = .italic
                    case .monospace:
                        swiftStyle = .monospace
                    case .spoiler:
                        swiftStyle = .spoiler
                    case .strikethrough:
                        swiftStyle = .strikethrough
                    }
                    bodyStyles.append(.init(swiftStyle, range: range))
                }
            }
            bodyRanges = .init(mentions: bodyMentions, styles: bodyStyles)
        } else {
            bodyRanges = nil
        }

        if let incomingMessage = chatItem.incoming {

            guard let authorAci = aciMap[chatItem.authorID] else {
                owsFailDebug("Missing author for message!")
                return
            }

            let messageBuilder = TSIncomingMessageBuilder.builder(
                thread: thread,
                timestamp: chatItem.dateReceived,
                authorAci: .init(authorAci),
                // TODO: this needs to be added to the proto
                sourceDeviceId: 1,
                messageBody: standardMessage.text?.body,
                bodyRanges: bodyRanges,
                attachmentIds: nil,
                // TODO: handle edit states
                editState: .none,
                // TODO: expose + set expire start time
                expiresInSeconds: UInt32(chatItem.expiresIn),
                quotedMessage: nil,
                contactShare: nil,
                linkPreview: nil,
                messageSticker: nil,
                serverTimestamp: nil,
                serverDeliveryTimestamp: chatItem.dateSent,
                serverGuid: nil,
                wasReceivedByUD: incomingMessage.sealedSender.negated,
                isViewOnceMessage: false,
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                giftBadge: nil,
                paymentNotification: nil
            )
            let message = messageBuilder.build()
            tsInteractionFetcher.insert(message, tx: tx)

        } else if let outgoingMessage = chatItem.outgoing {

            let messageBuilder = TSOutgoingMessageBuilder.builder(
                thread: thread,
                timestamp: chatItem.dateSent,
                messageBody: standardMessage.text?.body,
                bodyRanges: bodyRanges,
                attachmentIds: nil,
                // TODO: is this seconds or ms?
                expiresInSeconds: UInt32(chatItem.expiresIn),
                expireStartedAt: chatItem.expireStart,
                isVoiceMessage: false,
                groupMetaMessage: .unspecified,
                quotedMessage: nil,
                contactShare: nil,
                linkPreview: nil,
                messageSticker: nil,
                isViewOnceMessage: false,
                changeActionsProtoData: nil,
                additionalRecipients: nil,
                skippedRecipients: nil,
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                giftBadge: nil
            )

            let message = tsInteractionFetcher.insertMessageWithBuilder(messageBuilder, tx: tx)

            for sendStatus in outgoingMessage.sendStatus {
                let recipient: ServiceId
                if let aci = aciMap[sendStatus.recipientID] {
                    recipient = aci
                } else if let pni = pniMap[sendStatus.recipientID] {
                    recipient = pni
                } else {
                    continue
                }

                if let deliveryStatus = sendStatus.deliveryStatus {
                    tsInteractionFetcher.update(
                        message,
                        withRecipient: recipient,
                        status: deliveryStatus,
                        timestamp: sendStatus.timestamp,
                        wasSentByUD: sendStatus.sealedSender.negated,
                        tx: tx
                    )
                }
            }

            // TODO: mark the message as sent and whatnot.
        }
    }
}
