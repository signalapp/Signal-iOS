//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/**
 * Archives a group (``TSGroupThread``) as a ``BackupProto.Group``, which is a type of
 * ``BackupProto.Recipient``.
 *
 * This is a bit confusing, because ``TSThread`` mostly corresponds to ``BackupProto.Chat``,
 * and there will in fact _also_ be a ``BackupProto.Chat`` for the group thread. Its just that our
 * ``TSGroupThread`` contains all the metadata from both the Chat and Recipient representations
 * in the proto.
 */
public class MessageBackupGroupRecipientArchiver: MessageBackupRecipientDestinationArchiver {

    private let groupsV2: GroupsV2
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let storyStore: StoryStore
    private let threadStore: ThreadStore

    public init(
        groupsV2: GroupsV2,
        profileManager: MessageBackup.Shims.ProfileManager,
        storyStore: StoryStore,
        threadStore: ThreadStore
    ) {
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    private typealias GroupId = MessageBackup.GroupId

    public func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var errors = [ArchiveMultiFrameResult.ArchiveFrameError]()

        do {
            try threadStore.enumerateGroupThreads(tx: tx) { groupThread, _ in
                self.archiveGroupThread(
                    groupThread,
                    stream: stream,
                    context: context,
                    errors: &errors,
                    tx: tx
                )
            }
        } catch {
            // The enumeration of threads failed, not the processing of one single thread.
            return .completeFailure(.threadIteratorError(error))
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    private func archiveGroupThread(
        _ groupThread: TSGroupThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveMultiFrameResult.ArchiveFrameError],
        tx: DBReadTransaction
    ) {
        guard
            groupThread.isGroupV2Thread,
            let groupsV2Model = groupThread.groupModel as? TSGroupModelV2
        else {
            return
        }

        let groupId: GroupId = groupThread.groupId
        let recipientId = context.assignRecipientId(to: .group(groupId))

        let groupMasterKey: Data
        do {
            let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupsV2Model.secretParamsData))
            groupMasterKey = try groupSecretParams.getMasterKey().serialize().asData
        } catch {
            errors.append(.groupMasterKeyError(.group(groupId), error))
            return
        }

        let storyContext = storyStore.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: tx)

        var group = BackupProto.Group(
            masterKey: groupMasterKey,
            whitelisted: self.profileManager.isThread(inProfileWhitelist: groupThread, tx: tx),
            hideStory: storyContext.isHidden
        )
        switch groupThread.storyViewMode {
        case .disabled:
            group.storySendMode = .DISABLED
        case .explicit:
            group.storySendMode = .ENABLED
        default:
            group.storySendMode = .DEFAULT
        }

        Self.writeFrameToStream(
            stream,
            objectId: .group(groupId),
            frameBuilder: {
                var recipient = BackupProto.Recipient(id: recipientId.value)
                recipient.destination = .group(group)

                var frame = BackupProto.Frame()
                frame.item = .recipient(recipient)
                return frame
            }
        ).map { errors.append($0) }
    }

    static func canRestore(_ recipient: BackupProto.Recipient) -> Bool {
        switch recipient.destination {
        case .group:
            return true
        case nil, .contact, .distributionList, .selfRecipient, .releaseNotes:
            return false
        }
    }

    public func restore(
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        let groupProto: BackupProto.Group
        switch recipient.destination {
        case .group(let backupProtoGroup):
            groupProto = backupProtoGroup
        case nil, .contact, .distributionList, .selfRecipient, .releaseNotes:
            return .failure(
                [.developerError(
                    recipient.recipientId,
                    OWSAssertionError("Invalid proto for class")
                )]
            )
        }

        let masterKey = groupProto.masterKey

        guard groupsV2.isValidGroupV2MasterKey(masterKey) else {
            return .failure(
                [.invalidProtoData(recipient.recipientId, .invalidGV2MasterKey)]
            )
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        } catch {
            return .failure(
                [.invalidProtoData(recipient.recipientId, .invalidGV2MasterKey)]
            )
        }
        let groupId = groupContextInfo.groupId

        // TODO: support group creation.
        // group creation as written is async, and therefore needs refactoring
        // before it can be triggered from here (and waited on).
        // For now, assume this is called from the debug UI after we have synced
        // with storage service and have all the groups locally.
        guard let localThread = threadStore.fetchGroupThread(groupId: groupId, tx: tx) else {
            return .failure([.unimplemented(recipient.recipientId)])
        }
        switch (groupProto.storySendMode, localThread.storyViewMode) {
        case (.DISABLED, .disabled), (.ENABLED, .explicit), (.DEFAULT, _), (nil, _):
            // Nothing to change.
            break
        case (.DISABLED, _):
            threadStore.update(groupThread: localThread, withStorySendEnabled: false, updateStorageService: false, tx: tx)
        case (.ENABLED, _):
            threadStore.update(groupThread: localThread, withStorySendEnabled: true, updateStorageService: false, tx: tx)
        }
        let groupThread = localThread

        context[recipient.recipientId] = .group(groupId)

        if groupProto.whitelisted {
            profileManager.addToWhitelist(groupThread, tx: tx)
        }

        // We only need to actively hide, since unhidden is the default.
        if groupProto.hideStory {
            let storyContext = storyStore.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: tx)
            storyStore.updateStoryContext(storyContext, isHidden: true, tx: tx)
        }

        return .success
    }
}
