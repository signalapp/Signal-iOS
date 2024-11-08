//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension MessageBackup {
    struct AdHocCallAppId: MessageBackupLoggableId {
        private let callId: UInt64

        init(_ callId: UInt64) {
            self.callId = callId
        }

        public var typeLogString: String { "CallRecord" }
        public var idLogString: String { String(callId) }
    }

    struct AdHocCallId: MessageBackupLoggableId {
        private let callId: UInt64

        init(_ callId: UInt64) {
            self.callId = callId
        }

        public var typeLogString: String { "BackupProto_AdHocCall" }
        public var idLogString: String { String(callId) }
    }
}

public protocol MessageBackupAdHocCallArchiver: MessageBackupProtoArchiver {
    typealias AdHocCallAppId = MessageBackup.AdHocCallAppId
    typealias AdHocCallId = MessageBackup.AdHocCallId
    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<AdHocCallAppId>
    typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<AdHocCallAppId>
    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<AdHocCallId>
    typealias RestoreFrameError = MessageBackup.RestoreFrameError<AdHocCallId>

    /// Archive all ``CallRecord``s (they map to ``BackupProto_AdHocCall``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveAdHocCalls(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult

    /// Restore a single ``BackupProto_AdHocCall`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if the frame was restored without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ adHocCall: BackupProto_AdHocCall,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreFrameResult
}

public class MessageBackupAdHocCallArchiverImpl: MessageBackupAdHocCallArchiver {
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private let callRecordStore: CallRecordStore
    private let callLinkRecordStore: CallLinkRecordStore
    private let adHocCallRecordManager: AdHocCallRecordManager

    init(
        callRecordStore: CallRecordStore,
        callLinkRecordStore: CallLinkRecordStore,
        adHocCallRecordManager: AdHocCallRecordManager
    ) {
        self.callRecordStore = callRecordStore
        self.callLinkRecordStore = callLinkRecordStore
        self.adHocCallRecordManager = adHocCallRecordManager
    }

    public func archiveAdHocCalls(
        stream: any MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()
        do {
            try callRecordStore.enumerateAdHocCallRecords(tx: context.tx) { record in
                var adHocCallProto = BackupProto_AdHocCall()
                adHocCallProto.callID = record.callId
                adHocCallProto.callTimestamp = record.callBeganTimestamp

                // It's a cross-client decision that `state` can only
                // ever be `.generic` (even if the client state is
                // actually `.joined`).
                adHocCallProto.state = .generic

                switch record.conversationId {
                case .callLink(let callLinkRowId):
                    guard let value = context.recipientContext[.callLink(callLinkRowId)]?.value else {
                        partialErrors.append(.archiveFrameError(
                            .referencedRecipientIdMissing(.callLink(callLinkRowId)),
                            AdHocCallAppId(record.callId)
                        ))
                        return
                    }
                    adHocCallProto.recipientID = value
                default:
                    partialErrors.append(.archiveFrameError(
                        .adHocCallDoesNotHaveCallLinkAsConversationId,
                        AdHocCallAppId(record.callId)
                    ))
                    return
                }

                let error = Self.writeFrameToStream(
                    stream,
                    objectId: AdHocCallAppId(record.callId)
                ) {
                    var frame = BackupProto_Frame()
                    frame.adHocCall = adHocCallProto
                    return frame
                }

                if let error {
                    partialErrors.append(error)
                }
            }
        } catch {
            return .completeFailure(.fatalArchiveError(.adHocCallIteratorError(error)))
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialErrors)
        }
    }

    public func restore(
        _ adHocCall: BackupProto_AdHocCall,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreFrameResult {
        var partialErrors = [MessageBackup.RestoreFrameError<AdHocCallId>]()

        let state: CallRecord.CallStatus.CallLinkCallStatus
        switch adHocCall.state {
        case .generic:
            state = .generic
        case .unknownState:
            partialErrors.append(
                .restoreFrameError(.invalidProtoData(.adHocCallUnknownState),
                AdHocCallId(adHocCall.callID)
            ))
            state = .generic
        case .UNRECOGNIZED:
            partialErrors.append(
                .restoreFrameError(.invalidProtoData(.adHocCallUnrecognizedState),
                AdHocCallId(adHocCall.callID)
            ))
            state = .generic
        }

        let callLinkRowId: MessageBackup.CallLinkId
        let recipientId = adHocCall.callLinkRecipientId
        switch context.recipientContext[recipientId] {
        case .callLink(let callLinkId):
            callLinkRowId = callLinkId
        default:
            return .failure([.restoreFrameError(
                .invalidProtoData(.recipientOfAdHocCallWasNotCallLink),
                AdHocCallId(adHocCall.callID)
            )])
        }
        let adHocCallRecord = CallRecord(
            callId: adHocCall.callID,
            callLinkRowId: callLinkRowId,
            callStatus: state,
            callBeganTimestamp: adHocCall.callTimestamp
        )

        if let callLinkRecord = context.recipientContext[callLinkRowId] {
            do {
                var callLinkRecord = callLinkRecord
                callLinkRecord.didInsertCallRecord()
                try callLinkRecordStore.update(callLinkRecord, tx: context.tx)
            } catch {
                partialErrors.append(
                    .restoreFrameError(
                        .databaseInsertionFailed(error),
                        AdHocCallId(adHocCall.callID)
                    )
                )
            }
        }

        callRecordStore.insert(
            callRecord: adHocCallRecord,
            tx: context.tx
        )

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}
