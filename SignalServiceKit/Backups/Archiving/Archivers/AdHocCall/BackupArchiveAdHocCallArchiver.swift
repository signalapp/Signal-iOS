//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension BackupArchive {

    /// The ringRTC-provided call id for a call, shared across participating clients
    /// and persisted to the backup.
    /// Uniquely identifies an Ad-hoc Call in both the app and the backup.
    /// Representations of past non-ad-hoc calls also have call ids, but have
    /// alternative identifiers because they are represented as ChatItems.
    struct CallId: BackupArchive.LoggableId {
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

// MARK: -

public class BackupArchiveAdHocCallArchiver: BackupArchiveProtoStreamWriter {
    typealias AdHocCallAppId = BackupArchive.AdHocCallAppId
    typealias AdHocCallId = BackupArchive.AdHocCallId
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult<AdHocCallAppId>
    typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<AdHocCallAppId>
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult<AdHocCallId>
    typealias RestoreFrameError = BackupArchive.RestoreFrameError<AdHocCallId>

    private let callRecordStore: CallRecordStore
    private let callLinkRecordStore: CallLinkRecordStore
    private let adHocCallRecordManager: AdHocCallRecordManager

    init(
        callRecordStore: CallRecordStore,
        callLinkRecordStore: CallLinkRecordStore,
        adHocCallRecordManager: AdHocCallRecordManager,
    ) {
        self.callRecordStore = callRecordStore
        self.callLinkRecordStore = callLinkRecordStore
        self.adHocCallRecordManager = adHocCallRecordManager
    }

    // MARK: -

    /// Archive all ``CallRecord``s (they map to ``BackupProto_AdHocCall``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveAdHocCalls(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.ChatArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()
        do {
            try context.bencher.wrapEnumeration(
                callRecordStore.enumerateAdHocCallRecords(tx:block:),
                tx: context.tx,
            ) { record, frameBencher in
                try Task.checkCancellation()
                autoreleasepool {
                    let recordId = AdHocCallAppId(callRecord: record)

                    let callTimestamp = record.callBeganTimestamp
                    guard BackupArchive.Timestamps.isValid(callTimestamp) else {
                        partialErrors.append(.archiveFrameError(
                            .invalidAdHocCallTimestamp,
                            recordId,
                        ))
                        return
                    }

                    var adHocCallProto = BackupProto_AdHocCall()
                    adHocCallProto.callID = record.callId
                    adHocCallProto.callTimestamp = record.callBeganTimestamp

                    // It's a cross-client decision that `state` can only
                    // ever be `.generic` (even if the client state is
                    // actually `.joined`).
                    adHocCallProto.state = .generic

                    guard
                        let callLinkRecordId = BackupArchive.CallLinkRecordId(callRecordConversationId: record.conversationId)
                    else {
                        partialErrors.append(.archiveFrameError(
                            .adHocCallDoesNotHaveCallLinkAsConversationId,
                            recordId,
                        ))
                        return
                    }
                    guard let recipientId = context.recipientContext[.callLink(callLinkRecordId)] else {
                        partialErrors.append(.archiveFrameError(
                            .referencedRecipientIdMissing(.callLink(callLinkRecordId)),
                            recordId,
                        ))
                        return
                    }
                    adHocCallProto.recipientID = recipientId.value

                    let error = Self.writeFrameToStream(
                        stream,
                        objectId: recordId,
                        frameBencher: frameBencher,
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

    // MARK: -

    /// Restore a single ``BackupProto_AdHocCall`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if the frame was restored without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ adHocCall: BackupProto_AdHocCall,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreFrameResult {
        var partialErrors = [BackupArchive.RestoreFrameError<AdHocCallId>]()

        let callId = AdHocCallId(adHocCall: adHocCall)

        let state: CallRecord.CallStatus.CallLinkCallStatus
        switch adHocCall.state {
        case .generic:
            state = .generic
        case .unknownState, .UNRECOGNIZED:
            state = .generic
        }

        let callLinkRecordId: BackupArchive.CallLinkRecordId
        let recipientId = adHocCall.callLinkRecipientId
        switch context.recipientContext[recipientId] {
        case .callLink(let _callLinkRecordId):
            callLinkRecordId = _callLinkRecordId
        default:
            return .failure([.restoreFrameError(
                .invalidProtoData(.recipientOfAdHocCallWasNotCallLink),
                callId,
            )])
        }
        let adHocCallRecord = CallRecord(
            callId: callId.value,
            callLinkRowId: callLinkRecordId.rowId,
            callStatus: state,
            callBeganTimestamp: adHocCall.callTimestamp,
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
                        callId,
                    ),
                )
            }
        }

        do {
            try callRecordStore.insert(
                callRecord: adHocCallRecord,
                tx: context.tx,
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
