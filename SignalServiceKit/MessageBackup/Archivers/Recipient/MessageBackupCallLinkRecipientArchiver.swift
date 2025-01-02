//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC

extension MessageBackup {
    public struct CallLinkRecordId: Hashable, MessageBackupLoggableId {
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

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "CallLinkRecord" }
        public var idLogString: String { "\(rowId)" }
    }
}

public class MessageBackupCallLinkRecipientArchiver: MessageBackupProtoArchiver {
    typealias CallLinkRecordId = MessageBackup.CallLinkRecordId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address
    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>
    typealias RecipientId = MessageBackup.RecipientId
    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<RecipientId>

    private let callLinkStore: CallLinkRecordStore

    init(
        callLinkStore: CallLinkRecordStore
    ) {
        self.callLinkStore = callLinkStore
    }

    func archiveAllCallLinkRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()
        do {
            try self.callLinkStore.enumerateAll(tx: context.tx) { record in
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
                    if let expirationMs = record.expirationMs {
                        // Lacking an expiration is a valid state. It can occur 1) if we hadn't
                        // yet fetched the expiration from the server at the time of backup, or
                        // 2) if someone deletes a call link before we're able to fetch the
                        // expiration.
                        callLink.expirationMs = expirationMs
                    }

                    let recipientId = context.assignRecipientId(to: callLinkAppId)
                    Self.writeFrameToStream(
                        stream,
                        objectId: callLinkAppId
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
        context: MessageBackup.RecipientRestoringContext
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line
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

        var partialErrors = [MessageBackup.RestoreFrameError<RecipientId>]()

        let restrictions: CallLinkRecord.Restrictions
        switch callLinkProto.restrictions {
        case .adminApproval:
            restrictions = .adminApproval
        case .none:
            restrictions = .none
        case .unknown:
            restrictions = .unknown
        case .UNRECOGNIZED:
            partialErrors.append(.restoreFrameError(.invalidProtoData(.callLinkRestrictionsUnrecognizedType), recipient.recipientId))
            restrictions = .adminApproval
        }

        do {
            let record = try callLinkStore.insertFromBackup(
                rootKey: rootKey,
                adminPasskey: adminKey,
                name: callLinkProto.name,
                restrictions: restrictions,
                expiration: callLinkProto.expirationSec,
                isUpcoming: true, // will be set false later if we process a corresponding ad hoc call frame
                tx: context.tx
            )
            let callLinkRecordId = CallLinkRecordId(record)
            context[recipient.recipientId] = .callLink(callLinkRecordId)
            context[callLinkRecordId] = record
        } catch {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipient.recipientId)])
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}

fileprivate extension CallLinkRecord {
    var expirationMs: UInt64? {
        if let expiration {
            return UInt64(expiration) * 1000
        }
        return nil
    }
}

fileprivate extension BackupProto_CallLink {
    var expirationSec: UInt64 {
        self.expirationMs / 1000
    }
}
