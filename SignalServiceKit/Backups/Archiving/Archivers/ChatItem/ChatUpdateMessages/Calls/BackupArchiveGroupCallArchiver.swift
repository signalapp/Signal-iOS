//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class BackupArchiveGroupCallArchiver {
    typealias Details = BackupArchive.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = BackupArchive.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = BackupArchive.RestoreInteractionResult<Void>

    private let callRecordStore: CallRecordStore
    private let groupCallRecordManager: GroupCallRecordManager
    private let interactionStore: BackupArchiveInteractionStore

    init(
        callRecordStore: CallRecordStore,
        groupCallRecordManager: GroupCallRecordManager,
        interactionStore: BackupArchiveInteractionStore,
    ) {
        self.callRecordStore = callRecordStore
        self.groupCallRecordManager = groupCallRecordManager
        self.interactionStore = interactionStore
    }

    func archiveGroupCall(
        _ groupCallInteraction: OWSGroupCallMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        let associatedCallRecord: CallRecord? = callRecordStore.fetch(
            interactionRowId: groupCallInteraction.sqliteRowId!,
            tx: context.tx,
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
            case .group(.ringingMissedNotificationProfile): groupCallState = .missedNotificationProfile
            case .individual, .callLink:
                return .messageFailure([.archiveFrameError(
                    .groupCallRecordHadInvalidCallStatus,
                    BackupArchive.InteractionUniqueId(interaction: groupCallInteraction),
                )])
            }
        } else {
            // This call predates the introduction of call records.
            groupCallState = .generic
        }

        var partialErrors = [BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>]()

        /// The call record will store the best record of when the call began,
        /// since we update its timestamp if we learn the group call started
        /// earlier than we originally learned about it. If there's no call
        /// record, though, we can fall back to the interaction.
        let startedCallTimestamp: UInt64 = associatedCallRecord?.callBeganTimestamp ?? groupCallInteraction.timestamp

        switch
            BackupArchive.Timestamps.validateTimestamp(startedCallTimestamp)
                .bubbleUp(Details.self, partialErrors: &partialErrors)
        {
        case .continue:
            break
        case .bubbleUpError(let error):
            return error
        }

        var groupCallUpdate = BackupProto_GroupCall()
        groupCallUpdate.state = groupCallState
        groupCallUpdate.startedCallTimestamp = startedCallTimestamp
        if let associatedCallRecord {
            groupCallUpdate.callID = associatedCallRecord.callId
            groupCallUpdate.read = switch associatedCallRecord.unreadStatus {
            case .read: true
            case .unread: false
            }
            BackupArchive.Timestamps.setTimestampIfValid(
                from: associatedCallRecord,
                \.callEndedTimestamp,
                on: &groupCallUpdate,
                \.endedCallTimestamp,
                allowZero: false,
            )
        } else {
            /// This property is non-optional, but we only track it for calls
            /// with an `associatedCallRecord`. For those without, mark them as
            /// read.
            groupCallUpdate.read = true
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

        switch Details.validateAndBuild(
            interactionUniqueId: groupCallInteraction.uniqueInteractionId,
            author: .localUser,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: groupCallInteraction.timestamp,
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

    func restoreGroupCall(
        _ groupCall: BackupProto_GroupCall,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreChatUpdateMessageResult {
        let groupThread: TSGroupThread
        switch chatThread.threadType {
        case .groupV2(let _groupThread):
            groupThread = _groupThread
        case .contact:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.groupCallNotInGroupThread),
                chatItem.id,
            )])
        }

        let startedCallAci: Aci?
        if groupCall.hasStartedCallRecipientID {
            switch context.recipientContext.getAci(
                recipientId: BackupArchive.RecipientId(value: groupCall.startedCallRecipientID),
                forChatItemId: chatItem.id,
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
            sentAtTimestamp: chatItem.dateSent,
        )
        groupCallInteraction.wasRead = groupCall.read

        do {
            try interactionStore.insert(
                groupCallInteraction,
                in: chatThread,
                chatId: chatItem.typedChatId,
                startedCallAci: startedCallAci,
                wasRead: groupCall.read,
                context: context,
            )
        } catch let error {
            return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        if groupCall.hasCallID {
            let callDirection: CallRecord.CallDirection
            let callStatus: CallRecord.CallStatus.GroupCallStatus
            switch groupCall.state {
            case .unknownState, .UNRECOGNIZED:
                // Fallback to generic
                callDirection = .incoming
                callStatus = .generic
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
            case .missed:
                callDirection = .incoming
                callStatus = .ringingMissed
            case .missedNotificationProfile:
                callDirection = .incoming
                callStatus = .ringingMissedNotificationProfile
            case .outgoingRing:
                callDirection = .outgoing
                callStatus = .ringingAccepted
            }

            let groupCallRingerAci: Aci?
            if groupCall.hasRingerRecipientID {
                switch context.recipientContext.getAci(
                    recipientId: BackupArchive.RecipientId(value: groupCall.ringerRecipientID),
                    forChatItemId: chatItem.id,
                ) {
                case .found(let aci): groupCallRingerAci = aci
                case .missing(let restoreFrameError): return .messageFailure([restoreFrameError])
                }
            } else {
                groupCallRingerAci = nil
            }

            let callRecord: CallRecord
            do {
                callRecord = try groupCallRecordManager.createGroupCallRecord(
                    callId: groupCall.callID,
                    groupCallInteraction: groupCallInteraction,
                    groupCallInteractionRowId: groupCallInteraction.sqliteRowId!,
                    groupThreadRowId: chatThread.threadRowId,
                    callDirection: callDirection,
                    groupCallStatus: callStatus,
                    groupCallRingerAci: groupCallRingerAci,
                    callEventTimestamp: groupCall.startedCallTimestamp,
                    shouldSendSyncMessage: false,
                    tx: context.tx,
                )
                if groupCall.hasEndedCallTimestamp {
                    try callRecordStore.updateCallEndedTimestamp(
                        callRecord: callRecord,
                        callEndedTimestamp: groupCall.endedCallTimestamp,
                        tx: context.tx,
                    )
                }
                if groupCall.read {
                    try callRecordStore.markAsRead(callRecord: callRecord, tx: context.tx)
                }
            } catch {
                return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
            }
        }

        return .success(())
    }
}

private extension BackupArchive.RecipientRestoringContext {
    enum RecipientIdResult {
        case found(Aci)
        case missing(BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>)
    }

    func getAci(
        recipientId: BackupArchive.RecipientId,
        forChatItemId chatItemId: BackupArchive.ChatItemId,
    ) -> RecipientIdResult {
        guard let recipientAddress: Address = self[recipientId] else {
            return .missing(.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(recipientId)),
                chatItemId,
            ))
        }

        switch recipientAddress {
        case .localAddress:
            return .found(localIdentifiers.aci)
        case .contact(let contactAddress):
            guard let aci = contactAddress.aci else { fallthrough }
            return .found(aci)
        case .group, .distributionList, .releaseNotesChannel, .callLink:
            return .missing(.restoreFrameError(
                .invalidProtoData(.groupCallRecipientIdNotAnAci(recipientId)),
                chatItemId,
            ))
        }
    }
}
