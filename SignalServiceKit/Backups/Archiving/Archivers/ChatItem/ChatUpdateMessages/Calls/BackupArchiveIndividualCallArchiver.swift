//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class BackupArchiveIndividualCallArchiver {
    typealias Details = BackupArchive.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = BackupArchive.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = BackupArchive.RestoreInteractionResult<Void>

    private let callRecordStore: CallRecordStore
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: BackupArchiveInteractionStore

    init(
        callRecordStore: CallRecordStore,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: BackupArchiveInteractionStore,
    ) {
        self.callRecordStore = callRecordStore
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
    }

    func archiveIndividualCall(
        _ individualCallInteraction: TSCall,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        let associatedCallRecord: CallRecord? = callRecordStore.fetch(
            interactionRowId: individualCallInteraction.sqliteRowId!,
            tx: context.tx,
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
            case
                .incoming,
                .incomingAnsweredElsewhere,
                .outgoing:
                return .accepted
            case
                .outgoingIncomplete,
                .incomingIncomplete,
                .incomingDeclined,
                .incomingDeclinedElsewhere,
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

        var partialErrors = [BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>]()

        /// Prefer the call record timestamp if available, since it'll have the
        /// more accurate timestamp. (In practice this won't matter, since for
        /// 1:1 calls the call record takes the same "call started" timestamp as
        /// the interaction: when the call offer message arrives.)
        let startedCallTimestamp = associatedCallRecord?.callBeganTimestamp ?? individualCallInteraction.timestamp

        switch
            BackupArchive.Timestamps.validateTimestamp(startedCallTimestamp)
                .bubbleUp(Details.self, partialErrors: &partialErrors)
        {
        case .continue:
            break
        case .bubbleUpError(let error):
            return error
        }

        individualCallUpdate.startedCallTimestamp = startedCallTimestamp

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

        switch Details.validateAndBuild(
            interactionUniqueId: individualCallInteraction.uniqueInteractionId,
            author: .localUser,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: individualCallInteraction.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false,
            threadInfo: threadInfo,
            pinMessageDetails: nil,
            context: context.recipientContext,
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let details):
            if partialErrors.isEmpty {
                return .success(details)
            } else {
                return .partialFailure(details, partialErrors)
            }
        case .bubbleUpError(let error):
            return error
        }
    }

    func restoreIndividualCall(
        _ individualCall: BackupProto_IndividualCall,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreChatUpdateMessageResult {
        let contactThread: TSContactThread
        switch chatThread.threadType {
        case .contact(let _contactThread):
            contactThread = _contactThread
        case .groupV2:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.individualCallNotInContactThread),
                chatItem.id,
            )])
        }

        let callRecordDirection: CallRecord.CallDirection
        switch individualCall.direction {
        case .unknownDirection, .UNRECOGNIZED:
            // Fallback to incoming
            callRecordDirection = .incoming
        case .incoming:
            callRecordDirection = .incoming
        case .outgoing:
            callRecordDirection = .outgoing
        }

        let callInteractionType: RPRecentCallType
        let callRecordStatus: CallRecord.CallStatus.IndividualCallStatus
        switch (callRecordDirection, individualCall.state) {
        case (.incoming, .accepted), (.incoming, .unknownState), (.incoming, .UNRECOGNIZED):
            callInteractionType = .incoming
            callRecordStatus = .accepted
        case (.incoming, .notAccepted):
            callInteractionType = .incomingDeclined
            callRecordStatus = .notAccepted
        case (.incoming, .missed):
            callInteractionType = .incomingMissed
            callRecordStatus = .incomingMissed
        case (.incoming, .missedNotificationProfile):
            callInteractionType = .incomingMissedBecauseOfDoNotDisturb
            callRecordStatus = .incomingMissed
        case (.outgoing, .accepted), (.outgoing, .unknownState), (.outgoing, .UNRECOGNIZED):
            callInteractionType = .outgoing
            callRecordStatus = .accepted
        case (.outgoing, .notAccepted):
            callInteractionType = .outgoingIncomplete
            callRecordStatus = .notAccepted
        case (.outgoing, .missed), (.outgoing, .missedNotificationProfile):
            callInteractionType = .outgoingMissed
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
            // Fallback to audio
            callInteractionOfferType = .audio
            callRecordType = .audioCall
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
            sentAtTimestamp: chatItem.dateSent,
        )
        individualCallInteraction.wasRead = individualCall.read

        do {
            try interactionStore.insert(
                individualCallInteraction,
                in: chatThread,
                chatId: chatItem.typedChatId,
                callerAci: callerAci,
                wasRead: individualCall.read,
                context: context,
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
                    tx: context.tx,
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
