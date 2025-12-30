//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC

extension BackupArchive {
    public struct CallLinkRecordId: Hashable, BackupArchive.LoggableId {
        let rowId: Int64

        public init(_ callLinkRecord: CallLinkRecord) {
            self.rowId = callLinkRecord.id
        }

        public init?(callRecordConversationId: CallRecord.ConversationID) {
            switch callRecordConversationId {
            case .thread:
                return nil
            case .callLink(let callLinkRowId):
                self.rowId = callLinkRowId
            }
        }

        // MARK: BackupArchive.LoggableId

        public var typeLogString: String { "CallLinkRecord" }
        public var idLogString: String { "\(rowId)" }
    }
}

public class BackupArchiveCallLinkRecipientArchiver: BackupArchiveProtoStreamWriter {
    typealias CallLinkRecordId = BackupArchive.CallLinkRecordId
    typealias RecipientAppId = BackupArchive.RecipientArchivingContext.Address
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<RecipientAppId>
    typealias RecipientId = BackupArchive.RecipientId
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<RecipientId>

    private let callLinkStore: CallLinkRecordStore

    init(
        callLinkStore: CallLinkRecordStore,
    ) {
        self.callLinkStore = callLinkStore
    }

    func archiveAllCallLinkRecipients(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.RecipientArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()
        do {
            try context.bencher.wrapEnumeration(
                callLinkStore.enumerateAll(tx:block:),
                tx: context.tx,
            ) { record, frameBencher in
                try Task.checkCancellation()
                autoreleasepool {
                    var callLink = BackupProto_CallLink()
                    callLink.rootKey = record.rootKey.bytes
                    if let adminPasskey = record.adminPasskey {
                        // If there is no adminPasskey on the record, then the
                        // local user is not the call admin, and we leave this
                        // field blank on the proto.
                        callLink.adminKey = adminPasskey
                    }
                    if let name = record.name {
                        // If the default name is being used, just leave the field blank.
                        callLink.name = name
                    }
                    callLink.restrictions = { () -> BackupProto_CallLink.Restrictions in
                        if let restrictions = record.restrictions {
                            switch restrictions {
                            case .none: return .none
                            case .adminApproval: return .adminApproval
                            case .unknown: return .unknown
                            }
                        } else {
                            return .unknown
                        }
                    }()

                    let callLinkRecordId = CallLinkRecordId(record)
                    let callLinkAppId: RecipientAppId = .callLink(callLinkRecordId)
                    // Lacking an expiration is a valid state. It can occur 1) if we hadn't
                    // yet fetched the expiration from the server at the time of backup, or
                    // 2) if someone deletes a call link before we're able to fetch the
                    // expiration.
                    BackupArchive.Timestamps.setTimestampIfValid(
                        from: record,
                        \.expirationMs,
                        on: &callLink,
                        \.expirationMs,
                        allowZero: true,
                    )

                    owsAssertDebug(record.revoked != true, "call links should be deleted, not revoked")

                    let recipientId = context.assignRecipientId(to: callLinkAppId)
                    Self.writeFrameToStream(
                        stream,
                        objectId: callLinkAppId,
                        frameBencher: frameBencher,
                    ) {
                        var recipient = BackupProto_Recipient()
                        recipient.id = recipientId.value
                        recipient.destination = .callLink(callLink)
                        var frame = BackupProto_Frame()
                        frame.item = .recipient(recipient)
                        return frame
                    }.map { errors.append($0) }
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            return .completeFailure(.fatalArchiveError(.callLinkRecordIteratorError(error)))
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    func restoreCallLinkRecipientProto(
        _ callLinkProto: BackupProto_CallLink,
        recipient: BackupProto_Recipient,
        context: BackupArchive.RecipientRestoringContext,
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line,
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, recipient.recipientId, line: line)])
        }

        let rootKey: CallLinkRootKey
        do {
            rootKey = try CallLinkRootKey(callLinkProto.rootKey)
        } catch {
            return .failure([.restoreFrameError(.invalidProtoData(.callLinkInvalidRootKey), recipient.recipientId)])
        }

        let adminKey: Data?
        if callLinkProto.hasAdminKey {
            adminKey = callLinkProto.adminKey
        } else {
            // If the proto lacks an admin key, it means the local user
            // is not the admin of the call link.
            adminKey = nil
        }

        let restrictions: CallLinkRecord.Restrictions
        switch callLinkProto.restrictions {
        case .adminApproval:
            restrictions = .adminApproval
        case .none:
            restrictions = .none
        case .unknown, .UNRECOGNIZED:
            restrictions = .unknown
        }

        let hasAnyState: Bool = (
            !callLinkProto.name.isEmpty
                || restrictions != .unknown
                || callLinkProto.expirationMs != 0,
        )

        do {
            let record = try callLinkStore.insertFromBackup(
                rootKey: rootKey,
                adminPasskey: adminKey,
                name: hasAnyState ? callLinkProto.name.nilIfEmpty : nil,
                restrictions: hasAnyState ? restrictions : nil,
                revoked: hasAnyState ? false : nil,
                expiration: hasAnyState ? Int64(callLinkProto.expirationMs / 1000) : nil,
                isUpcoming: hasAnyState ? (adminKey != nil) : nil,
                tx: context.tx,
            )
            let callLinkRecordId = CallLinkRecordId(record)
            context[recipient.recipientId] = .callLink(callLinkRecordId)
            context[callLinkRecordId] = record
        } catch {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipient.recipientId)])
        }

        return .success
    }
}

private extension CallLinkRecord {
    var expirationMs: UInt64? {
        if let expiration {
            return UInt64(expiration) * 1000
        }
        return nil
    }
}
