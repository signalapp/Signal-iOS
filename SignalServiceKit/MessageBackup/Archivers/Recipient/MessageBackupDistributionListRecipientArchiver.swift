//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class MessageBackupDistributionListRecipientArchiver: MessageBackupRecipientDestinationArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    private let privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager
    private let storyStore: any StoryStore
    private let threadStore: any ThreadStore

    init(
        privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager,
        storyStore: any StoryStore,
        threadStore: any ThreadStore
    ) {
        self.privateStoryThreadDeletionManager = privateStoryThreadDeletionManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        do {
            // enumerate deleted threads
            for item in privateStoryThreadDeletionManager.allDeletedIdentifiers(tx: tx) {
                self.archiveDeletedStoryList(
                    distributionId: item,
                    stream: stream,
                    context: context,
                    errors: &errors,
                    tx: tx
                )
            }
            try threadStore.enumerateStoryThreads(tx: tx) { storyThread in
                self.archiveStoryThread(
                    storyThread,
                    stream: stream,
                    context: context,
                    errors: &errors,
                    tx: tx
                )

                return true
            }
        } catch {
            // The enumeration of threads failed, not the processing of one single thread.
            return .completeFailure(.fatalArchiveError(.threadIteratorError(error)))
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    private func archiveStoryThread(
        _ storyThread: TSPrivateStoryThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveFrameError],
        tx: DBReadTransaction
    ) {
        // Skip deleted distribution lists
        guard storyThread.storyViewMode != .disabled else { return }

        guard let distributionId = storyThread.distributionListIdentifier else {
            // This optionality is a result of the UUID initializer being failable.
            // This shouldn't be encountered in practice since the uniqueId is always generated from
            // a UUID (or 'My Story' identifier).  But if this is encountered, report an error and skip
            // this d-list with a generic 'missing identifier' message.
            owsFailDebug("Missing distributionListIdentifier for story distribution list")
            return
        }

        let distributionListAppId: RecipientAppId = .distributionList(distributionId)
        let recipientId = context.assignRecipientId(to: distributionListAppId)

        let memberRecipientIds = storyThread.addresses.compactMap { address -> UInt64? in
            guard let contactAddress = address.asSingleServiceIdBackupAddress() else {
                errors.append(.archiveFrameError(.invalidDistributionListMemberAddress, distributionListAppId))
                return nil
            }
            guard let recipientId = context[.contact(contactAddress)] else {
                errors.append(.archiveFrameError(.referencedRecipientIdMissing(.distributionList(distributionId)), distributionListAppId))
                return nil
            }
            return recipientId.value
        }

        // Ensure that explicit/blocklist have valid member recipient addresses
        let privacyMode: BackupProto.DistributionList.PrivacyMode? = {
            switch storyThread.storyViewMode {
            case .disabled:
                return nil
            case .default:
                guard memberRecipientIds.count == 0 else {
                    errors.append(.archiveFrameError(.distributionListUnexpectedRecipients, distributionListAppId))
                    return nil
                }
                return .ALL
            case .explicit:
                guard memberRecipientIds.count > 0 else {
                    errors.append(.archiveFrameError(.distributionListMissingRecipients, distributionListAppId))
                    return nil
                }
                return .ONLY_WITH
            case .blockList:
                guard memberRecipientIds.count > 0 else {
                    errors.append(.archiveFrameError(.distributionListMissingRecipients, distributionListAppId))
                    return nil
                }
                return .ALL_EXCEPT
            }
        }()

        guard let privacyMode else {
            // Error should have been recorded above, so just return here
            return
        }

        var distributionList = BackupProto.DistributionList(
            name: storyThread.name,
            allowReplies: storyThread.allowsReplies,
            privacyMode: privacyMode
        )
        distributionList.memberRecipientIds = memberRecipientIds

        var distributionListItem = BackupProto.DistributionListItem(distributionId: distributionId)
        distributionListItem.item = .distributionList(distributionList)

        Self.writeFrameToStream(stream, objectId: distributionListAppId) {
            var recipient = BackupProto.Recipient(id: recipientId.value)
            recipient.destination = .distributionList(distributionListItem)

            var frame = BackupProto.Frame()
            frame.item = .recipient(recipient)
            return frame
        }.map { errors.append($0) }
    }

    private func archiveDeletedStoryList(
        distributionId: Data,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveFrameError],
        tx: DBReadTransaction
    ) {
        let distributionListAppId: RecipientAppId = .distributionList(distributionId)

        guard let deletionTimestamp = privateStoryThreadDeletionManager.deletedAtTimestamp(
            forDistributionListIdentifier: distributionId,
            tx: tx
        ) else {
            errors.append(.archiveFrameError(.distributionListMissingDeletionTimestamp, distributionListAppId))
            return
        }

        let recipientId = context.assignRecipientId(to: distributionListAppId)

        var distributionList = BackupProto.DistributionListItem(distributionId: distributionId)
        distributionList.item = .deletionTimestamp(deletionTimestamp)

        Self.writeFrameToStream(stream, objectId: distributionListAppId) {
            var recipient = BackupProto.Recipient(id: recipientId.value)
            recipient.destination = .distributionList(distributionList)

            var frame = BackupProto.Frame()
            frame.item = .recipient(recipient)
            return frame
        }.map { errors.append($0) }
    }

    func restore(
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: any DBWriteTransaction
    ) -> RestoreFrameResult {

        let distributionListItemProto: BackupProto.DistributionListItem
        switch recipient.destination {
        case .distributionList(let backupProtoDistributionListItem):
            distributionListItemProto = backupProtoDistributionListItem
        case nil, .contact, .group, .releaseNotes, .selfRecipient, .callLink:
            return .failure([.restoreFrameError(
                .developerError(OWSAssertionError("Invalid proto for class")),
                recipient.recipientId
            )])
        }

        guard let distributionId = UUID(data: distributionListItemProto.distributionId) else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidDistributionListId),
                recipient.recipientId
            )])
        }

        let result: RestoreFrameResult
        switch distributionListItemProto.item {
        case .some(.deletionTimestamp(let deletionTimestamp)):
            // Restore deleted distribution lists identifiers. These are needed
            // to preserve the deleted distribution list entry in storage service
            // during a sync.  If these weren't backed up, there's a chance the deleted
            // list would be removed from storage service before the deletion would
            // be picked up by a linked device. Deleted lists that are too old will
            // be filtered by the `setDeletedAtTimestamp` method, so filtering isn't
            // necessary here.
            if deletionTimestamp > 0 {
                privateStoryThreadDeletionManager.recordDeletedAtTimestamp(
                    deletionTimestamp,
                    forDistributionListIdentifier: distributionId.data,
                    tx: tx
                )
                result = .success
            } else {
                result = .failure([.restoreFrameError(
                    .invalidProtoData(.invalidDistributionListDeletionTimestamp),
                    recipient.recipientId
                )])
            }
        case .some(.distributionList(let distributionListItemProto)):
            result = buildDistributionList(
                from: distributionListItemProto,
                distributionId: distributionId,
                recipientId: recipient.recipientId,
                context: context,
                tx: tx
            )
        case .none:
            result = .failure([.restoreFrameError(
                .developerError(OWSAssertionError("Invalid proto for class")),
                recipient.recipientId
            )])
        }

        context[recipient.recipientId] = .distributionList(distributionListItemProto.distributionId)
        return result
    }

    private func buildDistributionList(
        from distributionListProto: BackupProto.DistributionList,
        distributionId: UUID,
        recipientId: MessageBackup.RecipientId,
        context: MessageBackup.RecipientRestoringContext,
        tx: any DBWriteTransaction
    ) -> RestoreFrameResult {
        var error: RestoreFrameResult?

        let addresses = distributionListProto
            .memberRecipientIds
            .compactMap {
                switch context[RecipientId(value: $0)] {
                case .contact(let contactAddress):
                    return contactAddress.asInteropAddress()
                case .distributionList, .group, .localAddress, .releaseNotesChannel, .none:
                    error = .failure([.restoreFrameError(
                        .invalidProtoData(.invalidDistributionListMember(protoClass: BackupProto.DistributionList.self)),
                        recipientId
                    )])
                    return nil
                }
            }

        if let error {
            return error
        }

        let viewMode: TSThreadStoryViewMode? = {
            switch distributionListProto.privacyMode {
            case .ALL:
                return .default
            case .ALL_EXCEPT:
                return .blockList
            case .ONLY_WITH:
                return .explicit
            case .UNKNOWN:
                return nil
            }
        }()

        guard let viewMode else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidDistributionListPrivacyMode),
                recipientId
            )])
        }

        switch viewMode {
        case .blockList, .explicit:
            guard addresses.count > 0 else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.invalidDistributionListPrivacyModeMissingRequiredMembers),
                    recipientId
                )])
            }
        case .default, .disabled:
            break
        }

        // MyStory is created during warmCaches(), so it should be present at this point.
        // But to guard against any future changes, call getOrCreateMyStory() to ensure
        // it is present before updating with the incoming data.
        if TSPrivateStoryThread.myStoryUniqueId == distributionId.uuidString {
            let myStory = storyStore.getOrCreateMyStory(tx: tx)
            storyStore.update(
                storyThread: myStory,
                name: distributionListProto.name,
                allowReplies: distributionListProto.allowReplies,
                viewMode: viewMode,
                addresses: addresses,
                tx: tx
            )
        } else {
            let storyThread = TSPrivateStoryThread(
                uniqueId: distributionId.uuidString,
                name: distributionListProto.name,
                allowsReplies: distributionListProto.allowReplies,
                addresses: addresses,
                viewMode: viewMode
            )
            storyStore.insert(storyThread: storyThread, tx: tx)
        }

        return .success
    }

    static func canRestore(_ recipient: BackupProto.Recipient) -> Bool {
        switch recipient.destination {
        case .distributionList:
            return true
        case nil, .contact, .group, .selfRecipient, .releaseNotes, .callLink:
            return false
        }
    }
}
