//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class MessageBackupGroupCallArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private let callRecordStore: CallRecordStore
    private let groupCallRecordManager: GroupCallRecordManager
    private let interactionStore: InteractionStore

    init(
        callRecordStore: CallRecordStore,
        groupCallRecordManager: GroupCallRecordManager,
        interactionStore: InteractionStore
    ) {
        self.callRecordStore = callRecordStore
        self.groupCallRecordManager = groupCallRecordManager
        self.interactionStore = interactionStore
    }

    func archiveGroupCall(
        _ groupCallInteraction: OWSGroupCallMessage,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveChatUpdateMessageResult {
        let associatedCallRecord: CallRecord? = callRecordStore.fetch(
            interactionRowId: groupCallInteraction.sqliteRowId!,
            tx: tx
        )

        let groupCallState: BackupProto_GroupCall.State
        if let associatedCallRecord {
            switch associatedCallRecord.callStatus {
            case .group(.generic): groupCallState = .generic
            case .group(.joined): groupCallState = .joined
            case .group(.ringing): groupCallState = .ringing
            case .group(.ringingAccepted):
                switch associatedCallRecord.callDirection {
                case .incoming: groupCallState = .accepted
                case .outgoing: groupCallState = .outgoingRing
                }
            case .group(.ringingDeclined): groupCallState = .declined
            case .group(.ringingMissed): groupCallState = .missed
            case .individual:
                return .messageFailure([.archiveFrameError(
                    .groupCallRecordHadIndividualCallStatus,
                    MessageBackup.InteractionUniqueId(interaction: groupCallInteraction)
                )])
            }
        } else {
            // This call predates the introduction of call records.
            groupCallState = .generic
        }

        /// The call record will store the best record of when the call began,
        /// since we update its timestamp if we learn the group call started
        /// earlier than we originally learned about it. If there's no call
        /// record, though, we can fall back to the interaction.
        let startedCallTimestamp: UInt64 = associatedCallRecord?.callBeganTimestamp ?? groupCallInteraction.timestamp

        /// iOS doesn't currently track this, so we'll default-populate it.
        let endedCallTimestamp: UInt64 = 0

        var groupCallUpdate = BackupProto_GroupCall()
        groupCallUpdate.state = groupCallState
        groupCallUpdate.startedCallTimestamp = startedCallTimestamp
        groupCallUpdate.endedCallTimestamp = endedCallTimestamp
        if let associatedCallRecord {
            groupCallUpdate.callID = associatedCallRecord.callId
            groupCallUpdate.read = switch associatedCallRecord.unreadStatus {
            case .read: true
            case .unread: false
            }
        }

        if let ringerAci = associatedCallRecord?.groupCallRingerAci {
            switch context.recipientContext.getRecipientId(aci: ringerAci, forInteraction: groupCallInteraction) {
            case .found(let recipientId):
                groupCallUpdate.ringerRecipientID = recipientId.value
            case .missing(let archiveFrameError):
                return .messageFailure([archiveFrameError])
            }
        }

        if let creatorAci = groupCallInteraction.creatorUuid.flatMap({ Aci.parseFrom(aciString: $0) }) {
            switch context.recipientContext.getRecipientId(aci: creatorAci, forInteraction: groupCallInteraction) {
            case .found(let recipientId):
                groupCallUpdate.startedCallRecipientID = recipientId.value
            case .missing(let archiveFrameError):
                return .messageFailure([archiveFrameError])
            }
        }

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .groupCall(groupCallUpdate)

        let interactionArchiveDetails = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: groupCallInteraction.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage)
        )

        return .success(interactionArchiveDetails)
    }

    func restoreGroupCall(
        _ groupCall: BackupProto_GroupCall,
        chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreChatUpdateMessageResult {
        let groupThread: TSGroupThread
        switch chatThread.threadType {
        case .groupV2(let _groupThread):
            groupThread = _groupThread
        case .contact:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.groupCallNotInGroupThread),
                chatItem.id
            )])
        }

        let startedCallAci: Aci?
        if groupCall.hasStartedCallRecipientID {
            switch context.recipientContext.getAci(
                recipientId: MessageBackup.RecipientId(value: groupCall.startedCallRecipientID),
                forChatItemId: chatItem.id
            ) {
            case .found(let aci): startedCallAci = aci
            case .missing(let restoreFrameError): return .messageFailure([restoreFrameError])
            }
        } else {
            startedCallAci = nil
        }

        let groupCallInteraction = OWSGroupCallMessage(
            joinedMemberAcis: [],
            creatorAci: startedCallAci.map { AciObjC($0) },
            thread: groupThread,
            sentAtTimestamp: groupCall.startedCallTimestamp
        )
        interactionStore.insertInteraction(groupCallInteraction, tx: tx)

        if groupCall.hasCallID {
            let callDirection: CallRecord.CallDirection
            let callStatus: CallRecord.CallStatus.GroupCallStatus
            switch groupCall.state {
            case .unknownState, .UNRECOGNIZED:
                return .messageFailure([.restoreFrameError(.invalidProtoData(.groupCallUnrecognizedState), chatItem.id)])
            case .generic:
                callDirection = .incoming
                callStatus = .generic
            case .joined:
                callDirection = .incoming
                callStatus = .joined
            case .ringing:
                callDirection = .incoming
                callStatus = .ringing
            case .accepted:
                callDirection = .incoming
                callStatus = .ringingAccepted
            case .declined:
                callDirection = .incoming
                callStatus = .ringingDeclined
            case .missed, .missedNotificationProfile:
                callDirection = .incoming
                callStatus = .ringingMissed
            case .outgoingRing:
                callDirection = .outgoing
                callStatus = .ringingAccepted
            }

            let groupCallRingerAci: Aci?
            if groupCall.hasRingerRecipientID {
                switch context.recipientContext.getAci(
                    recipientId: MessageBackup.RecipientId(value: groupCall.ringerRecipientID),
                    forChatItemId: chatItem.id
                ) {
                case .found(let aci): groupCallRingerAci = aci
                case .missing(let restoreFrameError): return .messageFailure([restoreFrameError])
                }
            } else {
                groupCallRingerAci = nil
            }

            let callRecord = groupCallRecordManager.createGroupCallRecord(
                callId: groupCall.callID,
                groupCallInteraction: groupCallInteraction,
                groupCallInteractionRowId: groupCallInteraction.sqliteRowId!,
                groupThread: groupThread,
                groupThreadRowId: chatThread.threadRowId,
                callDirection: callDirection,
                groupCallStatus: callStatus,
                groupCallRingerAci: groupCallRingerAci,
                callEventTimestamp: groupCall.startedCallTimestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )

            if groupCall.read {
                callRecordStore.markAsRead(callRecord: callRecord, tx: tx)
            }
        }

        return .success(())
    }
}

// MARK: -

private extension MessageBackup.RecipientArchivingContext {
    enum RecipientIdResult {
        case found(MessageBackup.RecipientId)
        case missing(MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>)
    }

    func getRecipientId(
        aci: Aci,
        forInteraction interaction: TSInteraction,
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line
    ) -> RecipientIdResult {
        let contactAddress = MessageBackup.ContactAddress(aci: aci)

        if let recipientId = self[.contact(contactAddress)] {
            return .found(recipientId)
        }

        return .missing(.archiveFrameError(
            .referencedRecipientIdMissing(.contact(contactAddress)),
            MessageBackup.InteractionUniqueId(interaction: interaction),
            file: file, function: function, line: line
        ))
    }
}

private extension MessageBackup.RecipientRestoringContext {
    enum RecipientIdResult {
        case found(Aci)
        case missing(MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>)
    }

    func getAci(
        recipientId: MessageBackup.RecipientId,
        forChatItemId chatItemId: MessageBackup.ChatItemId
    ) -> RecipientIdResult {
        guard let recipientAddress: Address = self[recipientId] else {
            return .missing(.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(recipientId)),
                chatItemId
            ))
        }

        switch recipientAddress {
        case .localAddress:
            return .found(localIdentifiers.aci)
        case .contact(let contactAddress):
            guard let aci = contactAddress.aci else { fallthrough }
            return .found(aci)
        case .group, .distributionList, .releaseNotesChannel:
            return .missing(.restoreFrameError(
                .invalidProtoData(.groupCallRecipientIdNotAnAci(recipientId)),
                chatItemId
            ))
        }
    }
}
