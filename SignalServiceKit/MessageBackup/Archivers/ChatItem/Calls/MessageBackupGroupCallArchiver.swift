//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

final class MessageBackupGroupCallArchiver: MessageBackupInteractionArchiver {
    static let archiverType: MessageBackup.ChatItemArchiverType = .groupCall

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

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let groupCallInteraction = interaction as? OWSGroupCallMessage else {
            return .completeFailure(.fatalArchiveError(.developerError(OWSAssertionError("Invalid interaction type!"))))
        }

        let associatedCallRecord: CallRecord? = callRecordStore.fetch(
            interactionRowId: groupCallInteraction.sqliteRowId!,
            tx: tx
        )

        let groupCallState: BackupProto.GroupCall.State
        if let associatedCallRecord {
            switch associatedCallRecord.callStatus {
            case .group(.generic): groupCallState = .GENERIC
            case .group(.joined): groupCallState = .JOINED
            case .group(.ringing): groupCallState = .RINGING
            case .group(.ringingAccepted):
                switch associatedCallRecord.callDirection {
                case .incoming: groupCallState = .ACCEPTED
                case .outgoing: groupCallState = .OUTGOING_RING
                }
            case .group(.ringingDeclined): groupCallState = .DECLINED
            case .group(.ringingMissed): groupCallState = .MISSED
            case .individual:
                return .messageFailure([.archiveFrameError(
                    .groupCallRecordHadIndividualCallStatus,
                    MessageBackup.InteractionUniqueId(interaction: groupCallInteraction)
                )])
            }
        } else {
            // This call predates the introduction of call records.
            groupCallState = .GENERIC
        }

        /// The call record will store the best record of when the call began,
        /// since we update its timestamp if we learn the group call started
        /// earlier than we originally learned about it. If there's no call
        /// record, though, we can fall back to the interaction.
        let startedCallTimestamp: UInt64 = associatedCallRecord?.callBeganTimestamp ?? groupCallInteraction.timestamp

        /// iOS doesn't currently track this, so we'll default-populate it.
        let endedCallTimestamp: UInt64 = 0

        var groupCallUpdate = BackupProto.GroupCall(
            state: groupCallState,
            startedCallTimestamp: startedCallTimestamp,
            endedCallTimestamp: endedCallTimestamp
        )
        groupCallUpdate.callId = associatedCallRecord?.callId

        if let ringerAci = associatedCallRecord?.groupCallRingerAci {
            switch context.recipientContext.getRecipientId(aci: ringerAci, forInteraction: groupCallInteraction) {
            case .found(let recipientId):
                groupCallUpdate.ringerRecipientId = recipientId.value
            case .missing(let archiveFrameError):
                return .messageFailure([archiveFrameError])
            }
        }

        if let creatorAci = groupCallInteraction.creatorUuid.flatMap({ Aci.parseFrom(aciString: $0) }) {
            switch context.recipientContext.getRecipientId(aci: creatorAci, forInteraction: groupCallInteraction) {
            case .found(let recipientId):
                groupCallUpdate.startedCallRecipientId = recipientId.value
            case .missing(let archiveFrameError):
                return .messageFailure([archiveFrameError])
            }
        }

        var chatUpdateMessage = BackupProto.ChatUpdateMessage()
        chatUpdateMessage.update = .groupCall(groupCallUpdate)

        let interactionArchiveDetails = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: .directionless(BackupProto.ChatItem.DirectionlessMessageDetails()),
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage)
        )

        return .success(interactionArchiveDetails)
    }

    func restoreChatItem(
        _ chatItem: BackupProto.ChatItem,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let groupThread: TSGroupThread
        let groupCall: BackupProto.GroupCall
        do {
            switch thread {
            case .groupV2(let _groupThread): groupThread = _groupThread
            case .contact:
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.groupCallNotInGroupThread),
                    chatItem.id
                )])
            }

            switch chatItem.item {
            case .updateMessage(let updateMessage):
                switch updateMessage.update {
                case .groupCall(let _groupCall): groupCall = _groupCall
                default:
                    return .messageFailure([.restoreFrameError(
                        .developerError(OWSAssertionError("Non-group call update!")),
                        chatItem.id
                    )])
                }
            default:
                return .messageFailure([.restoreFrameError(
                    .developerError(OWSAssertionError("Non-chat update!")),
                    chatItem.id
                )])
            }
        }

        let startedCallAci: Aci?
        if let startedCallRecipientId = groupCall.startedCallRecipientId {
            switch context.recipientContext.getAci(
                recipientId: MessageBackup.RecipientId(value: startedCallRecipientId),
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

        if let callId = groupCall.callId {
            let callDirection: CallRecord.CallDirection
            let callStatus: CallRecord.CallStatus.GroupCallStatus
            switch groupCall.state {
            case .UNKNOWN_STATE:
                return .messageFailure([.restoreFrameError(.invalidProtoData(.groupCallUnrecognizedState), chatItem.id)])
            case .GENERIC:
                callDirection = .incoming
                callStatus = .generic
            case .JOINED:
                callDirection = .incoming
                callStatus = .joined
            case .RINGING:
                callDirection = .incoming
                callStatus = .ringing
            case .ACCEPTED:
                callDirection = .incoming
                callStatus = .ringingAccepted
            case .DECLINED:
                callDirection = .incoming
                callStatus = .ringingDeclined
            case .MISSED, .MISSED_NOTIFICATION_PROFILE:
                callDirection = .incoming
                callStatus = .ringingMissed
            case .OUTGOING_RING:
                callDirection = .outgoing
                callStatus = .ringingAccepted
            }

            let groupCallRingerAci: Aci?
            if let ringerRecipientId = groupCall.ringerRecipientId {
                switch context.recipientContext.getAci(
                    recipientId: MessageBackup.RecipientId(value: ringerRecipientId),
                    forChatItemId: chatItem.id
                ) {
                case .found(let aci): groupCallRingerAci = aci
                case .missing(let restoreFrameError): return .messageFailure([restoreFrameError])
                }
            } else {
                groupCallRingerAci = nil
            }

            _ = groupCallRecordManager.createGroupCallRecord(
                callId: callId,
                groupCallInteraction: groupCallInteraction,
                groupCallInteractionRowId: groupCallInteraction.sqliteRowId!,
                groupThread: groupThread,
                groupThreadRowId: groupThread.sqliteRowId!,
                callDirection: callDirection,
                groupCallStatus: callStatus,
                groupCallRingerAci: groupCallRingerAci,
                callEventTimestamp: groupCall.startedCallTimestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )
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
            file, function, line
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
        case .group, .distributionList:
            return .missing(.restoreFrameError(
                .invalidProtoData(.groupCallRecipientIdNotAnAci(recipientId)),
                chatItemId
            ))
        }
    }
}
