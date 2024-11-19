//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class MessageBackupIndividualCallArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private let callRecordStore: CallRecordStore
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: MessageBackupInteractionStore

    init(
        callRecordStore: CallRecordStore,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: MessageBackupInteractionStore
    ) {
        self.callRecordStore = callRecordStore
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
    }

    func archiveIndividualCall(
        _ individualCallInteraction: TSCall,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        let associatedCallRecord: CallRecord? = callRecordStore.fetch(
            interactionRowId: individualCallInteraction.sqliteRowId!,
            tx: context.tx
        )

        var individualCallUpdate = BackupProto_IndividualCall()
        individualCallUpdate.type = { () -> BackupProto_IndividualCall.TypeEnum in
            switch individualCallInteraction.offerType {
            case .audio: return .audioCall
            case .video: return .videoCall
            }
        }()
        individualCallUpdate.direction = { () -> BackupProto_IndividualCall.Direction in
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
                return .incoming
            case .outgoing, .outgoingIncomplete, .outgoingMissed:
                return .outgoing
            @unknown default:
                return .unknownDirection
            }
        }()
        individualCallUpdate.state = { () -> BackupProto_IndividualCall.State in
            switch individualCallInteraction.callType {
            case .incoming, .outgoing:
                return .accepted
            case
                    .outgoingIncomplete,
                    .incomingIncomplete,
                    .incomingDeclined,
                    .incomingDeclinedElsewhere,
                    .incomingAnsweredElsewhere,
                    .incomingBusyElsewhere:
                return .notAccepted
            case
                    .incomingMissed,
                    .incomingMissedBecauseOfChangedIdentity,
                    .incomingMissedBecauseBlockedSystemContact,
                    .outgoingMissed:
                return .missed
            case .incomingMissedBecauseOfDoNotDisturb:
                return .missedNotificationProfile
            @unknown default:
                return .unknownState
            }
        }()

        /// Prefer the call record timestamp if available, since it'll have the
        /// more accurate timestamp. (In practice this won't matter, since for
        /// 1:1 calls the call record takes the same "call started" timestamp as
        /// the interaction: when the call offer message arrives.)
        individualCallUpdate.startedCallTimestamp = associatedCallRecord?.callBeganTimestamp ?? individualCallInteraction.timestamp

        if let associatedCallRecord {
            individualCallUpdate.callID = associatedCallRecord.callId
            individualCallUpdate.read = switch associatedCallRecord.unreadStatus {
            case .read: true
            case .unread: false
            }
        } else {
            /// This property is non-optional, but we only track it for calls
            /// with an `associatedCallRecord`. For those without, mark them as
            /// read.
            individualCallUpdate.read = true
        }

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .individualCall(individualCallUpdate)

        let interactionArchiveDetails = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: individualCallInteraction.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false
        )

        return .success(interactionArchiveDetails)
    }

    func restoreIndividualCall(
        _ individualCall: BackupProto_IndividualCall,
        chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        let contactThread: TSContactThread
        switch chatThread.threadType {
        case .contact(let _contactThread):
            contactThread = _contactThread
        case .groupV2:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.individualCallNotInContactThread),
                chatItem.id
            )])
        }

        let callInteractionType: RPRecentCallType
        let callRecordDirection: CallRecord.CallDirection
        let callRecordStatus: CallRecord.CallStatus.IndividualCallStatus
        switch (individualCall.direction, individualCall.state) {
        case (.unknownDirection, _), (.UNRECOGNIZED, _):
            return .messageFailure([.restoreFrameError(.invalidProtoData(.individualCallUnrecognizedDirection), chatItem.id)])
        case (_, .unknownState), (_, .UNRECOGNIZED):
            return .messageFailure([.restoreFrameError(.invalidProtoData(.individualCallUnrecognizedState), chatItem.id)])
        case (.incoming, .accepted):
            callInteractionType = .incoming
            callRecordDirection = .incoming
            callRecordStatus = .accepted
        case (.incoming, .notAccepted):
            callInteractionType = .incomingDeclined
            callRecordDirection = .incoming
            callRecordStatus = .notAccepted
        case (.incoming, .missed):
            callInteractionType = .incomingMissed
            callRecordDirection = .incoming
            callRecordStatus = .incomingMissed
        case (.incoming, .missedNotificationProfile):
            callInteractionType = .incomingMissedBecauseOfDoNotDisturb
            callRecordDirection = .incoming
            callRecordStatus = .incomingMissed
        case (.outgoing, .accepted):
            callInteractionType = .outgoing
            callRecordDirection = .outgoing
            callRecordStatus = .accepted
        case (.outgoing, .notAccepted):
            callInteractionType = .outgoingIncomplete
            callRecordDirection = .outgoing
            callRecordStatus = .notAccepted
        case (.outgoing, .missed), (.outgoing, .missedNotificationProfile):
            callInteractionType = .outgoingMissed
            callRecordDirection = .outgoing
            callRecordStatus = .notAccepted
        }

        let callInteractionOfferType: TSRecentCallOfferType
        let callRecordType: CallRecord.CallType
        switch individualCall.type {
        case .audioCall:
            callInteractionOfferType = .audio
            callRecordType = .audioCall
        case .videoCall:
            callInteractionOfferType = .video
            callRecordType = .videoCall
        case .unknownType, .UNRECOGNIZED:
            return .messageFailure([.restoreFrameError(.invalidProtoData(.individualCallUnrecognizedType), chatItem.id)])
        }

        let callerAci: Aci?
        switch callRecordDirection {
        case .outgoing:
            callerAci = context.recipientContext.localIdentifiers.aci
        case .incoming:
            // Note: we may not _have_ an aci if this call
            // was made before the introduction of acis.
            callerAci = contactThread.contactAddress.aci
        }

        let individualCallInteraction = TSCall(
            callType: callInteractionType,
            offerType: callInteractionOfferType,
            thread: contactThread,
            sentAtTimestamp: chatItem.dateSent
        )

        do {
            try interactionStore.insert(
                individualCallInteraction,
                in: chatThread,
                chatId: chatItem.typedChatId,
                callerAci: callerAci,
                wasRead: individualCall.read,
                context: context
            )
        } catch let error {
            return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        if individualCall.hasCallID {
            let callRecord: CallRecord
            do {
                callRecord = try individualCallRecordManager.createRecordForInteraction(
                    individualCallInteraction: individualCallInteraction,
                    individualCallInteractionRowId: individualCallInteraction.sqliteRowId!,
                    contactThread: contactThread,
                    contactThreadRowId: chatThread.threadRowId,
                    callId: individualCall.callID,
                    callType: callRecordType,
                    callDirection: callRecordDirection,
                    individualCallStatus: callRecordStatus,
                    callEventTimestamp: individualCall.startedCallTimestamp,
                    shouldSendSyncMessage: false,
                    tx: context.tx
                )
                if individualCall.read {
                    try callRecordStore.markAsRead(callRecord: callRecord, tx: context.tx)
                }
            } catch {
                return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
            }
        }

        return .success(())
    }
}
