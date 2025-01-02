//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension MessageBackup {

    /// The ringRTC-provided call id for a call, shared across participating clients
    /// and persisted to the backup.
    /// Uniquely identifies an Ad-hoc Call in both the app and the backup.
    /// Representations of past non-ad-hoc calls also have call ids, but have
    /// alternative identifiers because they are represented as ChatItems.
    struct CallId: MessageBackupLoggableId {
        let value: UInt64

        init(callRecord: CallRecord) {
            self.value = callRecord.callId
        }

        init(adHocCall: BackupProto_AdHocCall) {
            self.value = adHocCall.callID
        }

        public var typeLogString: String { "CallRecord" }
        public var idLogString: String { String(value) }
    }

    // We use the same identifier (the CallId from RingRTC) to identify
    // ad-hoc calls both in the running app and in the backup proto.
    typealias AdHocCallAppId = CallId
    typealias AdHocCallId = CallId
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
    ) throws(CancellationError) -> ArchiveMultiFrameResult

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
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()
        do {
            try callRecordStore.enumerateAdHocCallRecords(tx: context.tx) { record in
                try Task.checkCancellation()
                autoreleasepool {
                    var adHocCallProto = BackupProto_AdHocCall()
                    adHocCallProto.callID = record.callId
                    adHocCallProto.callTimestamp = record.callBeganTimestamp

                    // It's a cross-client decision that `state` can only
                    // ever be `.generic` (even if the client state is
                    // actually `.joined`).
                    adHocCallProto.state = .generic

                    let recordId = AdHocCallAppId(callRecord: record)

                    guard
                        let callLinkRecordId = MessageBackup.CallLinkRecordId(callRecordConversationId: record.conversationId)
                    else {
                        partialErrors.append(.archiveFrameError(
                            .adHocCallDoesNotHaveCallLinkAsConversationId,
                            recordId
                        ))
                        return
                    }
                    guard let recipientId = context.recipientContext[.callLink(callLinkRecordId)] else {
                        partialErrors.append(.archiveFrameError(
                            .referencedRecipientIdMissing(.callLink(callLinkRecordId)),
                            recordId
                        ))
                        return
                    }
                    adHocCallProto.recipientID = recipientId.value

                    let error = Self.writeFrameToStream(
                        stream,
                        objectId: recordId
                    ) {
                        var frame = BackupProto_Frame()
                        frame.adHocCall = adHocCallProto
                        return frame
                    }

                    if let error {
                        partialErrors.append(error)
                    }
                }
            }
        } catch let error as CancellationError {
            throw error
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

        let callId = AdHocCallId(adHocCall: adHocCall)

        let state: CallRecord.CallStatus.CallLinkCallStatus
        switch adHocCall.state {
        case .generic:
            state = .generic
        case .unknownState:
            partialErrors.append(
                .restoreFrameError(.invalidProtoData(.adHocCallUnknownState),
                callId
            ))
            state = .generic
        case .UNRECOGNIZED:
            partialErrors.append(
                .restoreFrameError(.invalidProtoData(.adHocCallUnrecognizedState),
                callId
            ))
            state = .generic
        }

        let callLinkRecordId: MessageBackup.CallLinkRecordId
        let recipientId = adHocCall.callLinkRecipientId
        switch context.recipientContext[recipientId] {
        case .callLink(let _callLinkRecordId):
            callLinkRecordId = _callLinkRecordId
        default:
            return .failure([.restoreFrameError(
                .invalidProtoData(.recipientOfAdHocCallWasNotCallLink),
                callId
            )])
        }
        let adHocCallRecord = CallRecord(
            callId: callId.value,
            callLinkRowId: callLinkRecordId.rowId,
            callStatus: state,
            callBeganTimestamp: adHocCall.callTimestamp
        )

        if let callLinkRecord = context.recipientContext[callLinkRecordId] {
            do {
                var callLinkRecord = callLinkRecord
                callLinkRecord.didInsertCallRecord()
                try callLinkRecordStore.update(callLinkRecord, tx: context.tx)
            } catch {
                partialErrors.append(
                    .restoreFrameError(
                        .databaseInsertionFailed(error),
                        callId
                    )
                )
            }
        }

        do {
            try callRecordStore.insert(
                callRecord: adHocCallRecord,
                tx: context.tx
            )
        } catch {
            return .failure(partialErrors + [.restoreFrameError(.databaseInsertionFailed(error), callId)])
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}
