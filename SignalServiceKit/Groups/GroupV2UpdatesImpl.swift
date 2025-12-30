//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class GroupV2UpdatesImpl: GroupV2Updates {

    // This tracks the last time that groups were updated to the current
    // revision.
    private static let groupRefreshStore = KeyValueStore(collection: "groupRefreshStore")

    private var lastSuccessfulRefreshMap = LRUCache<GroupIdentifier, Date>(maxSize: 256)

    private let operationQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    init(appReadiness: AppReadiness) {
        SwiftSingletons.register(self)
    }

    // MARK: -

    // On launch, we refresh a randomly-selected group.
    public func autoRefreshGroup() async throws(CancellationError) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        try await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing()

        guard let groupInfoToRefresh = Self.findGroupToAutoRefresh() else {
            // We didn't find a group to refresh; abort.
            return
        }

        let groupId = groupInfoToRefresh.groupId
        let groupSecretParams = groupInfoToRefresh.groupSecretParams
        if let lastRefreshDate = groupInfoToRefresh.lastRefreshDate {
            let formattedDays = String(format: "%.1f", -lastRefreshDate.timeIntervalSinceNow / TimeInterval.day)
            Logger.info("auto-refreshing group: \(groupId) which hasn't been refreshed in \(formattedDays) days")
        } else {
            Logger.info("auto-refreshing group: \(groupId) which has never been refreshed")
        }

        do {
            try await self.refreshGroup(secretParams: groupSecretParams)
        } catch GroupsV2Error.localUserNotInGroup {
            Logger.warn("can't auto-refresh group unless we're a member")
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    private struct GroupInfo {
        let groupId: GroupIdentifier
        let groupSecretParams: GroupSecretParams
        let lastRefreshDate: Date?
    }

    private static func findGroupToAutoRefresh() -> GroupInfo? {
        // Enumerate the all v2 groups, trying to find the "best" one to refresh.
        // The "best" is the group that hasn't been refreshed in the longest time.
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            var groupInfoToRefresh: GroupInfo?
            TSGroupThread.anyEnumerate(
                transaction: transaction,
                batched: true,
            ) { thread, stop in
                guard
                    let groupThread = thread as? TSGroupThread,
                    let groupModel = groupThread.groupModel as? TSGroupModelV2,
                    groupModel.groupMembership.isLocalUserFullOrInvitedMember,
                    let groupSecretParams = try? groupModel.secretParams(),
                    let groupId = try? groupSecretParams.getPublicParams().getGroupIdentifier(),
                    !SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupId, transaction: transaction)
                else {
                    // Refreshing a group we're not a member of will throw errors
                    return
                }

                let storeKey = groupId.serialize().toHex()
                guard
                    let lastRefreshDate: Date = Self.groupRefreshStore.getDate(
                        storeKey,
                        transaction: transaction,
                    )
                else {
                    // If we find a group that we have no record of refreshing,
                    // pick that one immediately.
                    groupInfoToRefresh = GroupInfo(
                        groupId: groupId,
                        groupSecretParams: groupSecretParams,
                        lastRefreshDate: nil,
                    )
                    stop.pointee = true
                    return
                }

                // Don't auto-refresh groups more than once a week.
                let maxRefreshFrequencyInternal: TimeInterval = .week
                guard abs(lastRefreshDate.timeIntervalSinceNow) > maxRefreshFrequencyInternal else {
                    return
                }

                if
                    let otherGroupInfo = groupInfoToRefresh,
                    let otherLastRefreshDate = otherGroupInfo.lastRefreshDate,
                    otherLastRefreshDate < lastRefreshDate
                {
                    // We already found another group with an older refresh
                    // date, so prefer that one.
                    return
                }

                groupInfoToRefresh = GroupInfo(
                    groupId: groupId,
                    groupSecretParams: groupSecretParams,
                    lastRefreshDate: lastRefreshDate,
                )
            }
            return groupInfoToRefresh
        }
    }

    public func updateGroupWithChangeActions(
        groupId: GroupIdentifier,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        downloadedAvatars: GroupAvatarStateMap,
        transaction: DBWriteTransaction,
    ) throws -> TSGroupThread {

        guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction) else {
            throw OWSAssertionError("Not registered.")
        }
        let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
            groupThread: groupThread,
            localIdentifiers: localIdentifiers,
            changeActionsProto: changeActionsProto,
            downloadedAvatars: downloadedAvatars,
            options: [],
        )
        // The prior method throws if the revisions don't match.
        owsAssertDebug(changedGroupModel.newGroupModel.revision == changedGroupModel.oldGroupModel.revision + 1)

        GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            groupThread: groupThread,
            newGroupModel: changedGroupModel.newGroupModel,
            newDisappearingMessageToken: changedGroupModel.newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: changedGroupModel.newlyLearnedPniToAciAssociations,
            groupUpdateSource: changedGroupModel.updateSource,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction,
        )
        // The prior method always updates the revision because we've confirmed it's newer.
        owsAssertDebug((groupThread.groupModel as? TSGroupModelV2)?.revision == changedGroupModel.newGroupModel.revision)

        let authoritativeProfileKeys = changedGroupModel.profileKeys.filter {
            $0.key == changedGroupModel.updateSource.serviceIdUnsafeForLocalUserComparison()
        }
        GroupManager.storeProfileKeysFromGroupProtos(
            allProfileKeysByAci: changedGroupModel.profileKeys,
            authoritativeProfileKeysByAci: authoritativeProfileKeys,
            localIdentifiers: localIdentifiers,
            tx: transaction,
        )

        if let groupSendEndorsementsResponse {
            SSKEnvironment.shared.groupsV2Ref.handleGroupSendEndorsementsResponse(
                groupSendEndorsementsResponse,
                groupThreadId: groupThread.sqliteRowId!,
                secretParams: try changedGroupModel.newGroupModel.secretParams(),
                membership: groupThread.groupMembership,
                localAci: localIdentifiers.aci,
                tx: transaction,
            )
        }

        return groupThread
    }

    public func refreshGroupImpl(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions,
    ) async throws {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()

        let taskQueue: ConcurrentTaskQueue
        switch source {
        case .groupMessage:
            // The upstream caller handles the concurrency for these requests, so
            // create a dummy queue that just runs it immediately. This avoids deadlock
            // that may happen if group message processing gets stuck behind an
            // unrelated group refresh that's waiting for group message processing.
            taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
        case .other:
            taskQueue = self.operationQueue
        }

        try await taskQueue.run {
            let isThrottled = { () -> Bool in
                guard options.contains(.throttle) else {
                    return false
                }
                guard let lastSuccessfulRefreshDate = self.lastSuccessfulRefreshDate(forGroupId: groupId) else {
                    return false
                }
                // Don't auto-refresh more often than once every N minutes.
                let refreshFrequency: TimeInterval = .minute * 5
                return abs(lastSuccessfulRefreshDate.timeIntervalSinceNow) < refreshFrequency
            }()

            let databaseStorage = SSKEnvironment.shared.databaseStorageRef
            try databaseStorage.read { tx in
                // - If we're blocked, it's an immediate error
                if SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupId, transaction: tx) {
                    throw GroupsV2Error.groupBlocked
                }
            }

            if isThrottled {
                return
            }

            try await self.runUpdateOperation(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                source: source,
                options: options,
            )

            switch source {
            case .groupMessage:
                // We may or may not have updated to the very latest state, so we still
                // want to be able to refresh again when you open the conversation.
                break
            case .other:
                await self.didUpdateGroupToLatestRevision(groupId: groupId)
            }
        }
    }

    private func lastSuccessfulRefreshDate(forGroupId groupId: GroupIdentifier) -> Date? {
        lastSuccessfulRefreshMap[groupId]
    }

    private func didUpdateGroupToLatestRevision(groupId: GroupIdentifier) async {
        lastSuccessfulRefreshMap[groupId] = Date()
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Self.groupRefreshStore.setDate(Date(), key: groupId.serialize().hexadecimalString, transaction: tx)
        }
    }

    private func runUpdateOperation(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions,
    ) async throws {
        switch source {
        case .groupMessage:
            // If we're processing a message, we can't wait to finish processing
            // messages or we'll deadlock.
            break
        case .other:
            try await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing()
        }

        do {
            try await refreshGroupFromService(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                source: source,
                options: options,
            )
        } catch {
            Logger.warn("Group update failed: \(error)")
            switch error {
            case _ where error.isNetworkFailureOrTimeout:
                break
            case GroupsV2Error.localUserNotInGroup, GroupsV2Error.timeout:
                break
            case URLError.cancelled:
                break
            default:
                owsFailDebug("Group update failed: \(error)")
            }
            throw error
        }
    }
}

// MARK: - Refresh group from service

private extension GroupV2UpdatesImpl {

    // Fetch group state from service and apply.
    //
    // * Try to fetch and apply incremental "changes" -
    //   if the group already existing in the database.
    // * Failover to fetching and applying latest snapshot.
    // * We need to distinguish between retryable (network) errors
    //   and non-retryable errors.
    // * In the case of networking errors, we should do exponential
    //   backoff.
    // * If reachability changes, we should retry network errors
    //   immediately.
    func refreshGroupFromService(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions,
    ) async throws {
        do {
            // Try to use individual changes.
            try await self.fetchAndApplyChangeActionsFromService(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                source: source,
                options: options,
            )
        } catch {
            let shouldTrySnapshot = { () -> Bool in
                // This should not fail over in the case of networking problems.
                if error.isNetworkFailureOrTimeout {
                    Logger.warn("Error: \(error)")
                    return false
                }

                switch error {
                case GroupsV2Error.localUserNotInGroup:
                    // We can recover from some auth edge cases using a
                    // snapshot. For example, if we are joining via an
                    // invite link we will be unable to fetch change
                    // actions.
                    return true
                case GroupsV2Error.groupChangeProtoForIncompatibleRevision:
                    // If we got change protos for an incompatible revision,
                    // try and recover using a snapshot.
                    return true
                case URLError.cancelled:
                    return false
                default:
                    owsFailDebugUnlessNetworkFailure(error)
                    return false
                }
            }()

            guard shouldTrySnapshot else {
                throw error
            }

            // Failover to applying latest snapshot.
            try await self.fetchAndApplyCurrentGroupV2SnapshotFromService(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                options: options,
            )
        }
    }

    private func fetchAndApplyChangeActionsFromService(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions,
    ) async throws {
        while true {
            let groupsV2 = SSKEnvironment.shared.groupsV2Ref
            let response = try await groupsV2.fetchSomeGroupChangeActions(
                secretParams: secretParams,
                source: source,
            )

            var groupChanges = response.groupChanges
            var groupSendEndorsementsResponse = response.groupSendEndorsementsResponse

            switch source {
            case .groupMessage(let upThroughRevision):
                if groupChanges.contains(where: { $0.revision > upThroughRevision }) {
                    owsFailDebug("Ignoring revisions beyond \(upThroughRevision).")
                    groupChanges.removeAll(where: { $0.revision > upThroughRevision })
                    // We dropped the final revision, and this is valid for that.
                    groupSendEndorsementsResponse = nil
                }
            case .other:
                break
            }

            try await self.tryToApplyGroupChangesFromService(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                groupChanges: groupChanges,
                groupSendEndorsementsResponse: groupSendEndorsementsResponse,
                options: options,
            )

            if !response.shouldFetchMore {
                break
            }
        }
    }

    private func tryToApplyGroupChangesFromService(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupChanges: [GroupV2Change],
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        options: TSGroupModelOptions,
    ) async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }

            let groupV2Params = try GroupV2Params(groupSecretParams: secretParams)
            let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()

            let groupThread: TSGroupThread
            var localUserWasAddedBy: GroupUpdateSource?

            if let existingThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction) {
                groupThread = existingThread
                localUserWasAddedBy = nil
            } else {
                (groupThread, localUserWasAddedBy) = try self.insertThreadForGroupChanges(
                    groupId: groupId,
                    spamReportingMetadata: spamReportingMetadata,
                    groupV2Params: groupV2Params,
                    groupChanges: groupChanges,
                    groupModelOptions: options,
                    localIdentifiers: localIdentifiers,
                    transaction: transaction,
                )
            }

            var profileKeysByAci = [Aci: Data]()
            var authoritativeProfileKeysByAci = [Aci: Data]()
            for groupChange in groupChanges {
                let applyResult = try autoreleasepool {
                    try self.tryToApplySingleChangeFromService(
                        groupThread: groupThread,
                        groupV2Params: groupV2Params,
                        options: options,
                        groupChange: groupChange,
                        profileKeysByAci: &profileKeysByAci,
                        authoritativeProfileKeysByAci: &authoritativeProfileKeysByAci,
                        localIdentifiers: localIdentifiers,
                        spamReportingMetadata: spamReportingMetadata,
                        transaction: transaction,
                    )
                }

                if
                    let applyResult,
                    applyResult.wasLocalUserAddedByChange
                {
                    localUserWasAddedBy = applyResult.changeAuthor
                }
            }

            GroupManager.storeProfileKeysFromGroupProtos(
                allProfileKeysByAci: profileKeysByAci,
                authoritativeProfileKeysByAci: authoritativeProfileKeysByAci,
                localIdentifiers: localIdentifiers,
                tx: transaction,
            )

            let localUserWasAddedByBlockedUser: Bool
            switch localUserWasAddedBy {
            case nil, .unknown, .localUser:
                localUserWasAddedByBlockedUser = false
            case .legacyE164(let e164):
                localUserWasAddedByBlockedUser = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(
                    .legacyAddress(serviceId: nil, phoneNumber: e164.stringValue),
                    transaction: transaction,
                )
            case .aci(let aci):
                localUserWasAddedByBlockedUser = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(
                    .init(aci),
                    transaction: transaction,
                )
            case .rejectedInviteToPni:
                owsFailDebug("Local user added, but group update source was a PNI invite decline?")
                localUserWasAddedByBlockedUser = false
            }

            if localUserWasAddedByBlockedUser {
                // If we have been added to the group by a blocked user, we
                // should automatically leave the group. To that end, enqueue
                // a leave action after we've finished processing messages.
                _ = GroupManager.localLeaveGroupOrDeclineInvite(
                    groupThread: groupThread,
                    waitForMessageProcessing: true,
                    tx: transaction,
                )
            } else if
                let groupProfileKey = profileKeysByAci[localIdentifiers.aci],
                let localProfileKey = SSKEnvironment.shared.profileManagerRef.localUserProfile(tx: transaction)?.profileKey,
                groupProfileKey != localProfileKey.keyData
            {
                // If the final group state includes a stale profile key for the
                // local user, schedule an update to fix that. Note that we skip
                // this step if we are planning to leave the group via the block
                // above, as it's redundant.
                SSKEnvironment.shared.groupsV2Ref.updateLocalProfileKeyInGroup(
                    groupId: groupId.serialize(),
                    transaction: transaction,
                )
            }

            if let groupSendEndorsementsResponse {
                SSKEnvironment.shared.groupsV2Ref.handleGroupSendEndorsementsResponse(
                    groupSendEndorsementsResponse,
                    groupThreadId: groupThread.sqliteRowId!,
                    secretParams: secretParams,
                    membership: groupThread.groupMembership,
                    localAci: localIdentifiers.aci,
                    tx: transaction,
                )
            }
        }
    }

    // When learning about a v2 group for the first time, we need a snapshot of
    // the group's current state to get us started. From then on we prefer to
    // update the group using change actions, since those have more information.
    // Specifically, change actions record who performed the action, e.g. who
    // created the group or added us.
    //
    // We use this method to insert a thread if need be, so we can use change
    // actions going forward to keep the group up-to-date.
    private func insertThreadForGroupChanges(
        groupId: GroupIdentifier,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupV2Params: GroupV2Params,
        groupChanges: [GroupV2Change],
        groupModelOptions: TSGroupModelOptions,
        localIdentifiers: LocalIdentifiers,
        transaction: DBWriteTransaction,
    ) throws -> (TSGroupThread, addedToNewThreadBy: GroupUpdateSource?) {
        if TSGroupThread.fetch(forGroupId: groupId, tx: transaction) != nil {
            throw OWSAssertionError("Can't insert group thread that already exists.")
        }

        guard
            let firstGroupChange = groupChanges.first,
            let snapshot = firstGroupChange.snapshot
        else {
            throw OWSAssertionError("Missing first group change with snapshot")
        }

        let groupUpdateSource = try firstGroupChange.author(
            groupV2Params: groupV2Params,
            localIdentifiers: localIdentifiers,
        )

        var builder = try TSGroupModelBuilder.builderForSnapshot(
            groupV2Snapshot: snapshot,
            transaction: transaction,
        )
        builder.apply(options: groupModelOptions)

        let newGroupModel = try builder.buildAsV2()

        let newDisappearingMessageToken = snapshot.disappearingMessageToken
        let didAddLocalUserToV2Group = self.didAddLocalUserToV2Group(
            inGroupChange: firstGroupChange,
            groupV2Params: groupV2Params,
            localIdentifiers: localIdentifiers,
        )

        let groupThread = GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            didAddLocalUserToV2Group: didAddLocalUserToV2Group,
            infoMessagePolicy: .insert,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction,
        )

        // NOTE: We don't need to worry about profile keys here.  This method is
        // only used by tryToApplyGroupChangesFromServiceNow() which will take
        // care of that.

        return (
            groupThread,
            addedToNewThreadBy: didAddLocalUserToV2Group ? groupUpdateSource : nil,
        )
    }

    private struct ApplySingleChangeFromServiceResult {
        let changeAuthor: GroupUpdateSource
        let wasLocalUserAddedByChange: Bool
    }

    private func tryToApplySingleChangeFromService(
        groupThread: TSGroupThread,
        groupV2Params: GroupV2Params,
        options: TSGroupModelOptions,
        groupChange: GroupV2Change,
        profileKeysByAci: inout [Aci: Data],
        authoritativeProfileKeysByAci: inout [Aci: Data],
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: DBWriteTransaction,
    ) throws -> ApplySingleChangeFromServiceResult? {
        guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }

        // If this change is older than the group, there's nothing to do. If it's
        // the same, it probably means it's a snapshot we're supposed to re-apply.
        if groupChange.revision < oldGroupModel.revision {
            return nil
        }

        let logger = PrefixedLogger(
            prefix: "ApplySingleChange",
            suffix: "\(oldGroupModel.revision) -> \(groupChange.revision)",
        )

        let newGroupModel: TSGroupModel
        let newDisappearingMessageToken: DisappearingMessageToken?
        let newProfileKeys: [Aci: Data]
        let newlyLearnedPniToAciAssociations: [Pni: Aci]
        let groupUpdateSource: GroupUpdateSource

        // We should prefer to update models using the change action if we can,
        // since it contains information about the change author.
        if
            let changeActionsProto = groupChange.changeActionsProto,
            groupChange.revision == oldGroupModel.revision + 1,
            !oldGroupModel.isJoinRequestPlaceholder
        {
            logger.info("Applying changeActions.")

            let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
                groupThread: groupThread,
                localIdentifiers: localIdentifiers,
                changeActionsProto: changeActionsProto,
                downloadedAvatars: groupChange.downloadedAvatars,
                options: options,
            )
            newGroupModel = changedGroupModel.newGroupModel
            newDisappearingMessageToken = changedGroupModel.newDisappearingMessageToken
            newProfileKeys = changedGroupModel.profileKeys
            newlyLearnedPniToAciAssociations = changedGroupModel.newlyLearnedPniToAciAssociations
            groupUpdateSource = changedGroupModel.updateSource
        } else if let snapshot = groupChange.snapshot {
            logger.info("Applying snapshot.")

            var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: snapshot, transaction: transaction)
            builder.apply(options: options)
            newGroupModel = try builder.build()
            newDisappearingMessageToken = snapshot.disappearingMessageToken
            newProfileKeys = snapshot.profileKeys
            newlyLearnedPniToAciAssociations = [:]
            // Snapshots don't have a single author, so we don't know the source.
            groupUpdateSource = .unknown
        } else {
            // We had a group change proto with no snapshot, but the change was
            // not a single revision update.
            throw GroupsV2Error.groupChangeProtoForIncompatibleRevision
        }

        GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            groupThread: groupThread,
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction,
        )

        switch groupUpdateSource {
        case .unknown, .legacyE164, .rejectedInviteToPni, .localUser:
            break
        case .aci(let groupUpdateSourceAci):
            if let groupUpdateProfileKey = newProfileKeys[groupUpdateSourceAci] {
                authoritativeProfileKeysByAci[groupUpdateSourceAci] = groupUpdateProfileKey
            }
        }

        // Merge known profile keys, always taking latest.
        profileKeysByAci.merge(newProfileKeys) { _, latest in latest }

        return ApplySingleChangeFromServiceResult(
            changeAuthor: groupUpdateSource,
            wasLocalUserAddedByChange: didAddLocalUserToV2Group(
                inGroupChange: groupChange,
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers,
            ),
        )
    }

    // MARK: - Current Snapshot

    private func fetchAndApplyCurrentGroupV2SnapshotFromService(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        options: TSGroupModelOptions,
    ) async throws {
        let snapshotResponse = try await SSKEnvironment.shared.groupsV2Ref.fetchLatestSnapshot(
            secretParams: secretParams,
            justUploadedAvatars: nil,
        )

        let groupV2Snapshot = snapshotResponse.groupSnapshot

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
            let localAci = localIdentifiers.aci

            let profileManager = SSKEnvironment.shared.profileManagerRef
            let localProfileKey = profileManager.localUserProfile(tx: transaction)?.profileKey

            var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot, transaction: transaction)
            builder.apply(options: options)

            let groupId = try secretParams.getPublicParams().getGroupIdentifier()
            if
                let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction),
                let oldGroupModel = groupThread.groupModel as? TSGroupModelV2,
                oldGroupModel.revision == builder.groupV2Revision
            {
                // Preserve certain transient properties if overwriting a model
                // at the same revision.
                if oldGroupModel.didJustAddSelfViaGroupLink {
                    builder.didJustAddSelfViaGroupLink = true
                }
            }

            let newGroupModel = try builder.buildAsV2()
            let newDisappearingMessageToken = groupV2Snapshot.disappearingMessageToken
            // groupUpdateSource is unknown because we don't know the
            // author(s) of changes reflected in the snapshot.
            let groupUpdateSource: GroupUpdateSource = .unknown
            let groupThread = GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                newlyLearnedPniToAciAssociations: [:], // Not available from snapshots
                groupUpdateSource: groupUpdateSource,
                didAddLocalUserToV2Group: false,
                infoMessagePolicy: .insert,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction,
            )

            GroupManager.storeProfileKeysFromGroupProtos(
                allProfileKeysByAci: groupV2Snapshot.profileKeys,
                localIdentifiers: localIdentifiers,
                tx: transaction,
            )

            // If the group state includes a stale profile key for the
            // local user, schedule an update to fix that.
            if let localProfileKey, let profileKey = groupV2Snapshot.profileKeys[localAci], profileKey != localProfileKey.keyData {
                SSKEnvironment.shared.groupsV2Ref.updateLocalProfileKeyInGroup(groupId: newGroupModel.groupId, transaction: transaction)
            }

            if let groupSendEndorsementsResponse = snapshotResponse.groupSendEndorsementsResponse {
                SSKEnvironment.shared.groupsV2Ref.handleGroupSendEndorsementsResponse(
                    groupSendEndorsementsResponse,
                    groupThreadId: groupThread.sqliteRowId!,
                    secretParams: secretParams,
                    membership: groupV2Snapshot.groupMembership,
                    localAci: localAci,
                    tx: transaction,
                )
            }
        }
    }

    private func didAddLocalUserToV2Group(
        inGroupChange groupChange: GroupV2Change,
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers,
    ) -> Bool {
        let localAci = localIdentifiers.aci
        if groupChange.revision == 0 {
            // Revision 0 is a special case and won't have actions to
            // reflect the initial membership.
            return true
        }
        guard let changeActionsProto = groupChange.changeActionsProto else {
            // We're missing a change here, so we can't assume this is how we got into the group.
            return false
        }

        for action in changeActionsProto.addMembers {
            do {
                guard let member = action.added else {
                    continue
                }
                guard let userId = member.userID else {
                    continue
                }
                // Some userIds/uuidCiphertexts can be validated by
                // the service. This is one.
                let aci = try groupV2Params.aci(for: userId)
                if aci == localAci {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promotePendingMembers {
            do {
                let uuidCiphertext: UuidCiphertext
                if let userId = action.userID {
                    uuidCiphertext = try UuidCiphertext(contents: userId)
                } else if let presentationData = action.presentation {
                    let presentation = try ProfileKeyCredentialPresentation(contents: presentationData)
                    uuidCiphertext = try presentation.getUuidCiphertext()
                } else {
                    throw OWSAssertionError("Missing userId.")
                }

                let aci = try groupV2Params.serviceId(for: uuidCiphertext)
                if aci == localAci {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promotePniPendingMembers {
            do {
                guard let userId = action.userID else {
                    throw OWSAssertionError("Missing userID.")
                }
                let aci = try groupV2Params.aci(for: userId)
                if aci == localAci {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promoteRequestingMembers {
            do {
                guard let userId = action.userID else {
                    throw OWSAssertionError("Missing userID.")
                }
                // Some userIds/uuidCiphertexts can be validated by
                // the service. This is one.
                let aci = try groupV2Params.aci(for: userId)
                if aci == localAci {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        return false
    }
}

// MARK: -

extension GroupsV2Error: IsRetryableProvider {
    public var isRetryableProvider: Bool {
        if self.isNetworkFailureOrTimeout {
            return true
        }

        switch self {
        case
            .conflictingChangeOnService,
            .timeout:
            return true
        case
            .localUserNotInGroup,
            .cannotBuildGroupChangeProto_conflictingChange,
            .cannotBuildGroupChangeProto_tooManyMembers,
            .localUserIsNotARequestingMember,
            .cantApplyChangesToPlaceholder,
            .expiredGroupInviteLink,
            .groupBlocked,
            .localUserBlockedFromJoining,
            .groupChangeProtoForIncompatibleRevision,
            .serviceRequestHitRecoverable400:
            return false
        }
    }
}

private extension GroupV2Change {
    func author(
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers,
    ) throws -> GroupUpdateSource {
        if let changeActionsProto {
            return try changeActionsProto.updateSource(
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers,
            ).0
        }
        return .unknown
    }
}

public extension GroupsProtoGroupChangeActions {

    func updateSource(
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers,
    ) throws -> (GroupUpdateSource, ServiceId?) {
        func compareToLocal(
            source: GroupUpdateSource,
            serviceId: ServiceId,
        ) -> (GroupUpdateSource, ServiceId) {
            if localIdentifiers.contains(serviceId: serviceId) {
                return (.localUser(originalSource: source), serviceId)
            }

            return (source, serviceId)
        }

        guard let changeAuthorUserId: Data = self.sourceUserID else {
            owsFailDebug("Explicit changes should always have authors")
            return (.unknown, nil)
        }

        let serviceId = try groupV2Params.serviceId(for: changeAuthorUserId)
        switch serviceId.concreteType {
        case .aci(let aci):
            return compareToLocal(
                source: .aci(aci),
                serviceId: aci,
            )
        case .pni(let pni):
            /// At the time of writing, the only change actions with a PNI
            /// author are accepting or declining a PNI invite.
            ///
            /// If future updates to change actions introduce more actions with
            /// PNI authors, differentiate them here. The best time to
            /// differentiate is when we have access to the raw change actions.
            if
                self.deletePendingMembers.count == 1,
                let firstDeletePendingMember = self.deletePendingMembers.first,
                let firstDeletePendingMemberUserId = firstDeletePendingMember.deletedUserID,
                let firstDeletePendingMemberPni = try? groupV2Params.serviceId(for: firstDeletePendingMemberUserId) as? Pni
            {
                guard firstDeletePendingMemberPni == pni else {
                    owsFailDebug("Canary: PNI from change author doesn't match service ID in delete pending member change action!")
                    return (.unknown, nil)
                }

                return compareToLocal(
                    source: .rejectedInviteToPni(pni),
                    serviceId: pni,
                )
            } else if
                self.promotePniPendingMembers.count == 1,
                let firstPromotePniPendingMember = self.promotePniPendingMembers.first,
                let firstPromotePniPendingMemberAciUserId = firstPromotePniPendingMember.userID,
                let firstPromotePniPendingMemberAci = try? groupV2Params.serviceId(for: firstPromotePniPendingMemberAciUserId) as? Aci,
                let firstPromotePniPendingMemberPniUserId = firstPromotePniPendingMember.pni,
                let firstPromotePniPendingMemberPni = try? groupV2Params.serviceId(for: firstPromotePniPendingMemberPniUserId) as? Pni
            {
                guard firstPromotePniPendingMemberPni == pni else {
                    owsFailDebug("Canary: PNI from change author doesn't match service ID in promote PNI pending member change action!")
                    return (.unknown, nil)
                }

                /// While the service ID we received as the group update source
                /// from the server was a PNI, we know (thanks to the change
                /// action itself) the associated ACI. Since the ACI is how
                /// we're going to address this user going forward, we'll
                /// claim starting now that's who authored the change action.
                return compareToLocal(
                    source: .aci(firstPromotePniPendingMemberAci),
                    serviceId: firstPromotePniPendingMemberAci,
                )
            } else if
                self.addMembers.count == 1,
                let addMemberAction = self.addMembers.first,
                addMemberAction.joinFromInviteLink,
                let firstPniMemberAddedByLinkUserId = addMemberAction.added?.userID,
                let firstPniMemberAddedByLinkAci = try? groupV2Params.serviceId(for: firstPniMemberAddedByLinkUserId) as? Aci
            {
                /// While the service ID we received as the group update source
                /// from the server was a PNI, we know (thanks to the change
                /// action itself) the associated ACI. Since the ACI is how
                /// we're going to address this user going forward, we'll
                /// claim starting now that's who authored the change action.
                /// Note that this particular situation is legacy behavior and should
                /// eventually stop happening in the future.
                owsFailDebug("Canary: Legacy change action received from PNI change author!")
                return compareToLocal(
                    source: .aci(firstPniMemberAddedByLinkAci),
                    serviceId: firstPniMemberAddedByLinkAci,
                )
            } else if
                self.addRequestingMembers.count == 1,
                let addRequestingMemebers = self.addRequestingMembers.first,
                let firstPniMemberRequestingAddUserId = addRequestingMemebers.added?.userID,
                let firstPniMemberRequestingAddAci = try? groupV2Params.serviceId(for: firstPniMemberRequestingAddUserId) as? Aci
            {
                /// While the service ID we received as the group update source
                /// from the server was a PNI, we know (thanks to the change
                /// action itself) the associated ACI. Since the ACI is how
                /// we're going to address this user going forward, we'll
                /// claim starting now that's who authored the change action.
                /// Note that this particular situation is legacy behavior and should
                /// eventually stop happening in the future.
                owsFailDebug("Canary: Legacy change action received from PNI change author!")
                return compareToLocal(
                    source: .aci(firstPniMemberRequestingAddAci),
                    serviceId: firstPniMemberRequestingAddAci,
                )
            } else {
                owsFailDebug("Canary: unknown type of PNI-authored group update!")
                return (.unknown, nil)
            }
        }
    }
}
