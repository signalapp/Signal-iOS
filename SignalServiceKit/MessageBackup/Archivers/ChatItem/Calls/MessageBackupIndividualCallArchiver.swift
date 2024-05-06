//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

final class MessageBackupIndividualCallArchiver: MessageBackupInteractionArchiver {
    static let archiverType: MessageBackup.ChatItemArchiverType = .individualCall

    private let callRecordStore: CallRecordStore
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: InteractionStore

    init(
        callRecordStore: CallRecordStore,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: InteractionStore
    ) {
        self.callRecordStore = callRecordStore
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
    }

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let individualCallInteraction = interaction as? TSCall else {
            return .completeFailure(.fatalArchiveError(.developerError(OWSAssertionError("Invalid interaction type!"))))
        }

        let associatedCallRecord: CallRecord? = callRecordStore.fetch(
            interactionRowId: individualCallInteraction.sqliteRowId!,
            tx: tx
        )

        var individualCallUpdate = BackupProto.IndividualCall(
            type: { () -> BackupProto.IndividualCall.Type_ in
                switch individualCallInteraction.offerType {
                case .audio: return .AUDIO_CALL
                case .video: return .VIDEO_CALL
                }
            }(),
            direction: { () -> BackupProto.IndividualCall.Direction in
                switch individualCallInteraction.callType {
                case
                        .incoming,
                        .incomingIncomplete,
                        .incomingMissed,
                        .incomingMissedBecauseOfChangedIdentity,
                        .incomingMissedBecauseOfDoNotDisturb,
                        .incomingMissedBecauseBlockedSystemContact,
                        .incomingDeclined,
                        .incomingDeclinedElsewhere,
                        .incomingAnsweredElsewhere,
                        .incomingBusyElsewhere:
                    return .INCOMING
                case .outgoing, .outgoingIncomplete, .outgoingMissed:
                    return .OUTGOING
                @unknown default:
                    return .UNKNOWN_DIRECTION
                }
            }(),
            state: { () -> BackupProto.IndividualCall.State in
                switch individualCallInteraction.callType {
                case .incoming, .outgoing:
                    return .ACCEPTED
                case
                        .outgoingIncomplete,
                        .incomingIncomplete,
                        .incomingDeclined,
                        .incomingDeclinedElsewhere,
                        .incomingAnsweredElsewhere,
                        .incomingBusyElsewhere:
                    return .NOT_ACCEPTED
                case
                        .incomingMissed,
                        .incomingMissedBecauseOfChangedIdentity,
                        .incomingMissedBecauseBlockedSystemContact,
                        .outgoingMissed:
                    return .MISSED
                case .incomingMissedBecauseOfDoNotDisturb:
                    return .MISSED_NOTIFICATION_PROFILE
                @unknown default:
                    return .UNKNOWN_STATE
                }
            }(),
            startedCallTimestamp: individualCallInteraction.timestamp
        )
        individualCallUpdate.callId = associatedCallRecord?.callId

        var chatUpdateMessage = BackupProto.ChatUpdateMessage()
        chatUpdateMessage.update = .individualCall(individualCallUpdate)

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
        let contactThread: TSContactThread
        let individualCall: BackupProto.IndividualCall
        do {
            switch thread {
            case .contact(let _contactThread): contactThread = _contactThread
            case .groupV2:
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.individualCallNotInContactThread),
                    chatItem.id
                )])
            }

            switch chatItem.item {
            case .updateMessage(let updateMessage):
                switch updateMessage.update {
                case .individualCall(let _individualCall): individualCall = _individualCall
                default:
                    return .messageFailure([.restoreFrameError(
                        .developerError(OWSAssertionError("Non-individual call update!")),
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

        let callInteractionType: RPRecentCallType
        let callRecordDirection: CallRecord.CallDirection
        let callRecordStatus: CallRecord.CallStatus.IndividualCallStatus
        switch (individualCall.direction, individualCall.state) {
        case (.UNKNOWN_DIRECTION, _):
            return .messageFailure([.restoreFrameError(.invalidProtoData(.individualCallUnrecognizedDirection), chatItem.id)])
        case (_, .UNKNOWN_STATE):
            return .messageFailure([.restoreFrameError(.invalidProtoData(.individualCallUnrecognizedState), chatItem.id)])
        case (.INCOMING, .ACCEPTED):
            callInteractionType = .incoming
            callRecordDirection = .incoming
            callRecordStatus = .accepted
        case (.INCOMING, .NOT_ACCEPTED):
            callInteractionType = .incomingDeclined
            callRecordDirection = .incoming
            callRecordStatus = .notAccepted
        case (.INCOMING, .MISSED):
            callInteractionType = .incomingMissed
            callRecordDirection = .incoming
            callRecordStatus = .incomingMissed
        case (.INCOMING, .MISSED_NOTIFICATION_PROFILE):
            callInteractionType = .incomingMissedBecauseOfDoNotDisturb
            callRecordDirection = .incoming
            callRecordStatus = .incomingMissed
        case (.OUTGOING, .ACCEPTED):
            callInteractionType = .outgoing
            callRecordDirection = .outgoing
            callRecordStatus = .accepted
        case (.OUTGOING, .NOT_ACCEPTED):
            callInteractionType = .outgoingIncomplete
            callRecordDirection = .outgoing
            callRecordStatus = .notAccepted
        case (.OUTGOING, .MISSED), (.OUTGOING, .MISSED_NOTIFICATION_PROFILE):
            callInteractionType = .outgoingMissed
            callRecordDirection = .outgoing
            callRecordStatus = .notAccepted
        }

        let callInteractionOfferType: TSRecentCallOfferType
        let callRecordType: CallRecord.CallType
        switch individualCall.type {
        case .AUDIO_CALL:
            callInteractionOfferType = .audio
            callRecordType = .audioCall
        case .VIDEO_CALL:
            callInteractionOfferType = .video
            callRecordType = .videoCall
        case .UNKNOWN_TYPE:
            return .messageFailure([.restoreFrameError(.invalidProtoData(.individualCallUnrecognizedType), chatItem.id)])
        }

        let individualCallInteraction = TSCall(
            callType: callInteractionType,
            offerType: callInteractionOfferType,
            thread: contactThread,
            sentAtTimestamp: individualCall.startedCallTimestamp
        )
        interactionStore.insertInteraction(individualCallInteraction, tx: tx)

        if let callId = individualCall.callId {
            individualCallRecordManager.createRecordForInteraction(
                individualCallInteraction: individualCallInteraction,
                individualCallInteractionRowId: individualCallInteraction.sqliteRowId!,
                contactThread: contactThread,
                contactThreadRowId: contactThread.sqliteRowId!,
                callId: callId,
                callType: callRecordType,
                callDirection: callRecordDirection,
                individualCallStatus: callRecordStatus,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        return .success(())
    }
}
