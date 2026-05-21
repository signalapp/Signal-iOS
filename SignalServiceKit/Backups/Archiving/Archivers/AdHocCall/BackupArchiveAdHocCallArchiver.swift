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
    struct CallId {
        let value: UInt64

        init(callRecord: CallRecord) {
            self.value = callRecord.callId
        }

        init(adHocCall: BackupProto_AdHocCall) {
            self.value = adHocCall.callID
        }
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
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult
    typealias ArchiveFrameError = BackupArchive.ArchiveFrameError
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult
    typealias RestoreFrameError = BackupArchive.RestoreFrameError

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

        try context.bencher.wrapEnumeration(
            tx: context.tx,
            enumerationBlock: { tx, block throws(CancellationError) in
                try callRecordStore.enumerateAdHocCallRecords(tx: tx, block: block)
            },
            perEnumerantBlock: { record, frameBencher -> Bool in
                let callTimestamp = record.callBeganTimestamp
                guard BackupArchive.Timestamps.isValid(callTimestamp) else {
                    partialErrors.append(.archiveFrameError(.invalidAdHocCallTimestamp))
                    return true
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
                    partialErrors.append(.archiveFrameError(.adHocCallDoesNotHaveCallLinkAsConversationId))
                    return true
                }
                guard let recipientId = context.recipientContext[.callLink(callLinkRecordId)] else {
                    partialErrors.append(.archiveFrameError(
                        .referencedRecipientIdMissing(.callLink(callLinkRecordId)),
                    ))
                    return true
                }
                adHocCallProto.recipientID = recipientId.value

                let error: ArchiveFrameError? = Self.writeFrameToStream(
                    stream,
                    frameBencher: frameBencher,
                ) {
                    var frame = BackupProto_Frame()
                    frame.adHocCall = adHocCallProto
                    return frame
                }

                if let error {
                    partialErrors.append(error)
                }

                return true
            },
        )

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
            return .failure([.restoreFrameError(.invalidProtoData(.recipientOfAdHocCallWasNotCallLink))])
        }
        let adHocCallRecord = CallRecord(
            callId: callId.value,
            callLinkRowId: callLinkRecordId.rowId,
            callStatus: state,
            callBeganTimestamp: adHocCall.callTimestamp,
        )

        if let callLinkRecord = context.recipientContext[callLinkRecordId] {
            var callLinkRecord = callLinkRecord
            callLinkRecord.didInsertCallRecord()
            callLinkRecordStore.update(callLinkRecord, tx: context.tx)
        }

        callRecordStore.insert(
            callRecord: adHocCallRecord,
            tx: context.tx,
        )

        return .success
    }
}
