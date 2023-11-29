//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/**
 * Archives a group (``TSGroupThread``) as a ``BackupProtoGroup``, which is a type of
 * ``BackupProtoRecipient``.
 *
 * This is a bit confusing, because ``TSThread`` mostly corresponds to ``BackupProtoChat``,
 * and there will in fact _also_ be a ``BackupProtoChat`` for the group thread. Its just that our
 * ``TSGroupThread`` contains all the metadata from both the Chat and Recipient representations
 * in the proto.
 */
public class CloudBackupGroupRecipientArchiver: CloudBackupRecipientDestinationArchiver {

    private let groupsV2: GroupsV2
    private let profileManager: CloudBackup.Shims.ProfileManager
    private let storyFinder: CloudBackup.Shims.StoryFinder
    private let tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher

    public init(
        groupsV2: GroupsV2,
        profileManager: CloudBackup.Shims.ProfileManager,
        storyFinder: CloudBackup.Shims.StoryFinder,
        tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher
    ) {
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.storyFinder = storyFinder
        self.tsThreadFetcher = tsThreadFetcher
    }

    private typealias GroupId = CloudBackup.RecipientArchivingContext.Address.GroupId

    public func archiveRecipients(
        stream: CloudBackupProtoOutputStream,
        context: CloudBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveFramesResult {
        var errors = [ArchiveFramesResult.Error]()

        do {
            try tsThreadFetcher.enumerateAllGroupThreads(tx: tx) { groupThread in
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
            return .completeFailure(error)
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    private func archiveGroupThread(
        _ groupThread: TSGroupThread,
        stream: CloudBackupProtoOutputStream,
        context: CloudBackup.RecipientArchivingContext,
        errors: inout [ArchiveFramesResult.Error],
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
            errors.append(.init(objectId: recipientId, error: .groupMasterKeyError(error)))
            return
        }

        // TODO: instead of doing per-thread fetches, we should bulk load
        // some of these fetched fields into memory to avoid db round trips.
        let groupBuilder = BackupProtoGroup.builder(
            masterKey: groupMasterKey,
            whitelisted: self.profileManager.isThread(inProfileWhitelist: groupThread, tx: tx),
            hideStory: self.storyFinder.isStoryHidden(forGroupThread: groupThread, tx: tx) ?? false
        )
        switch groupThread.storyViewMode {
        case .disabled:
            groupBuilder.setStorySendMode(.disabled)
        case .explicit:
            groupBuilder.setStorySendMode(.enabled)
        default:
            groupBuilder.setStorySendMode(.default)
        }

        let recipientBuilder = BackupProtoRecipient.builder(id: recipientId.value)

        Self.writeFrameToStream(stream, frameBuilder: { frameBuilder in
            let groupProto = try groupBuilder.build()
            recipientBuilder.setGroup(groupProto)
            let recipientProto = try recipientBuilder.build()
            frameBuilder.setRecipient(recipientProto)
            return try frameBuilder.build()
        }).map { errors.append($0.asArchiveFramesError(objectId: recipientId)) }
    }

    static func canRestore(_ recipient: BackupProtoRecipient) -> Bool {
        return recipient.group != nil
    }

    public func restore(
        _ recipient: BackupProtoRecipient,
        context: CloudBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        guard let groupProto = recipient.group else {
            owsFail("Invalid proto for class")
        }

        let masterKey = groupProto.masterKey

        guard groupsV2.isValidGroupV2MasterKey(masterKey) else {
            owsFailDebug("Invalid master key.")
            return .failure(recipient.recipientId, .invalidProtoData)
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        } catch {
            owsFailDebug("Invalid master key.")
            return .failure(recipient.recipientId, .invalidProtoData)
        }
        let groupId = groupContextInfo.groupId

        var needsUpdate = false

        // TODO: support group creation.
        // group creation as written is async, and therefore needs refactoring
        // before it can be triggered from here (and waited on).
        // For now, assume this is called from the debug UI after we have synced
        // with storage service and have all the groups locally.
        guard let localThread = tsThreadFetcher.fetch(groupId: groupId, tx: tx) else {
            return .failure(recipient.recipientId, .databaseInsertionFailed(OWSAssertionError("Unimplemented")))
        }
        let localStorySendMode = localThread.storyViewMode.storageServiceMode
        switch (groupProto.storySendMode, localThread.storyViewMode) {
        case (.disabled, .disabled), (.enabled, .explicit), (.default, _), (nil, _):
            // Nothing to change.
            break
        case (.disabled, _):
            tsThreadFetcher.updateWithStorySendEnabled(false, groupThread: localThread, tx: tx)
        case (.enabled, _):
            tsThreadFetcher.updateWithStorySendEnabled(true, groupThread: localThread, tx: tx)
        }
        let groupThread = localThread

        context[recipient.recipientId] = .group(groupId)

        if groupProto.whitelisted {
            profileManager.addToWhitelist(groupThread, tx: tx)
        }

        if groupProto.hideStory {
            let storyContext = storyFinder.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: tx)
            storyFinder.setStoryContextHidden(storyContext, tx: tx)
        }

        return .success
    }
}
