//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class GroupV2UpdatesImpl {

    // This tracks the last time that groups were updated to the current
    // revision.
    private static let groupRefreshStore = KeyValueStore(collection: "groupRefreshStore")

    private var lastSuccessfulRefreshMap = LRUCache<Data, Date>(maxSize: 256)

    private let operationQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    init(appReadiness: AppReadiness) {
        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            Task { await self.autoRefreshGroupOnLaunch() }
        }
    }

    // MARK: -

    // On launch, we refresh a few randomly-selected groups.
    private func autoRefreshGroupOnLaunch() async {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing().awaitable()

        guard let groupInfoToRefresh = Self.findGroupToAutoRefresh() else {
            // We didn't find a group to refresh; abort.
            return
        }

        let groupId = groupInfoToRefresh.groupId
        let groupSecretParams = groupInfoToRefresh.groupSecretParams
        if let lastRefreshDate = groupInfoToRefresh.lastRefreshDate {
            let formattedDays = String(format: "%.1f", -lastRefreshDate.timeIntervalSinceNow/kDayInterval)
            Logger.info("Auto-refreshing group: \(groupId.base64EncodedString()) which hasn't been refreshed in \(formattedDays) days.")
        } else {
            Logger.info("Auto-refreshing group: \(groupId.base64EncodedString()) which has never been refreshed.")
        }

        do {
            try await self.refreshGroup(secretParams: groupSecretParams)
        } catch GroupsV2Error.localUserNotInGroup {
            Logger.warn("Can't auto-refresh group unless we're a member")
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    private struct GroupInfo {
        let groupId: Data
        let groupSecretParams: GroupSecretParams
        let lastRefreshDate: Date?
    }

    private static func findGroupToAutoRefresh() -> GroupInfo? {
        // Enumerate the all v2 groups, trying to find the "best" one to refresh.
        // The "best" is the group that hasn't been refreshed in the longest
        // time.
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            var groupInfoToRefresh: GroupInfo?
            TSGroupThread.anyEnumerate(
                transaction: transaction,
                batched: true
            ) { (thread, stop) in
                guard
                    let groupThread = thread as? TSGroupThread,
                    let groupModel = groupThread.groupModel as? TSGroupModelV2,
                    groupModel.groupMembership.isLocalUserFullOrInvitedMember,
                    let groupSecretParams = try? groupModel.secretParams(),
                    !SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupThread.groupId, transaction: transaction)
                else {
                    // Refreshing a group we're not a member of will throw errors
                    return
                }

                let storeKey = groupThread.groupId.hexadecimalString
                guard let lastRefreshDate: Date = Self.groupRefreshStore.getDate(
                    storeKey,
                    transaction: transaction.asV2Read
                ) else {
                    // If we find a group that we have no record of refreshing,
                    // pick that one immediately.
                    groupInfoToRefresh = GroupInfo(
                        groupId: groupThread.groupId,
                        groupSecretParams: groupSecretParams,
                        lastRefreshDate: nil
                    )
                    stop.pointee = true
                    return
                }

                // Don't auto-refresh groups more than once a week.
                let maxRefreshFrequencyInternal: TimeInterval = kWeekInterval
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
                    groupId: groupThread.groupId,
                    groupSecretParams: groupSecretParams,
                    lastRefreshDate: lastRefreshDate
                )
            }
            return groupInfoToRefresh
        }
    }
}

// MARK: - GroupV2UpdatesSwift

extension GroupV2UpdatesImpl: GroupV2Updates {

    public func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        downloadedAvatars: GroupV2DownloadedAvatars,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread {

        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
            throw OWSAssertionError("Not registered.")
        }
        let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
            groupThread: groupThread,
            localIdentifiers: localIdentifiers,
            changeActionsProto: changeActionsProto,
            downloadedAvatars: downloadedAvatars,
            options: []
        )
        // The prior method throws if the revisions don't match.
        owsAssertDebug(changedGroupModel.newGroupModel.revision == changedGroupModel.oldGroupModel.revision + 1)

        try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            groupThread: groupThread,
            newGroupModel: changedGroupModel.newGroupModel,
            newDisappearingMessageToken: changedGroupModel.newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: changedGroupModel.newlyLearnedPniToAciAssociations,
            groupUpdateSource: changedGroupModel.updateSource,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction
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
            tx: transaction
        )

        if let groupSendEndorsementsResponse {
            SSKEnvironment.shared.groupsV2Ref.handleGroupSendEndorsementsResponse(
                groupSendEndorsementsResponse,
                groupThreadId: groupThread.sqliteRowId!,
                secretParams: try changedGroupModel.newGroupModel.secretParams(),
                membership: groupThread.groupMembership,
                localAci: localIdentifiers.aci,
                tx: transaction.asV2Write
            )
        }

        return groupThread
    }

    public func refreshGroupImpl(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions
    ) async throws {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier().serialize().asData

        let isThrottled = { () -> Bool in
            guard options.contains(.throttle) else {
                return false
            }
            guard let lastSuccessfulRefreshDate = self.lastSuccessfulRefreshDate(forGroupId: groupId) else {
                return false
            }
            // Don't auto-refresh more often than once every N minutes.
            let refreshFrequency: TimeInterval = kMinuteInterval * 5
            return abs(lastSuccessfulRefreshDate.timeIntervalSinceNow) < refreshFrequency
        }()

        try SSKEnvironment.shared.databaseStorageRef.read { tx in
            // - If we're blocked, it's an immediate error
            if SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupId, transaction: tx) {
                throw GroupsV2Error.groupBlocked
            }
        }

        if isThrottled {
            return
        }

        try await self.operationQueue.run {
            try await Retry.performWithBackoff(maxAttempts: 3) {
                try await self.runUpdateOperation(
                    secretParams: secretParams,
                    spamReportingMetadata: spamReportingMetadata,
                    source: source,
                    options: options
                )
            }
        }

        switch source {
        case .groupMessage:
            // We may or may not have updated to the very latest state, so we still
            // want to be able to refresh again when you open the conversation.
            break
        case .other:
            await self.didUpdateGroupToLatestRevision(groupId: groupId)
        }
    }

    private func lastSuccessfulRefreshDate(forGroupId groupId: Data) -> Date? {
        lastSuccessfulRefreshMap[groupId]
    }

    private func didUpdateGroupToLatestRevision(groupId: Data) async {
        lastSuccessfulRefreshMap[groupId] = Date()
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Self.groupRefreshStore.setDate(Date(), key: groupId.hexadecimalString, transaction: tx.asV2Write)
        }
    }

    private func runUpdateOperation(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions
    ) async throws {
        switch source {
        case .groupMessage:
            // If we're processing a message, we can't wait to finish processing
            // messages or we'll deadlock.
            break
        case .other:
            await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing().awaitable()
        }

        do {
            try await refreshGroupFromService(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                source: source,
                options: options
            )
        } catch {
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Group update failed: \(error)")
            } else {
                switch error {
                case GroupsV2Error.localUserNotInGroup, GroupsV2Error.timeout, GroupsV2Error.missingGroupChangeProtos:
                    Logger.warn("Group update failed: \(error)")
                default:
                    owsFailDebug("Group update failed: \(error)")
                }
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
        options: TSGroupModelOptions
    ) async throws {
        try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()

        do {
            // Try to use individual changes.
            try await Promise.wrapAsync {
                try await self.fetchAndApplyChangeActionsFromService(
                    secretParams: secretParams,
                    spamReportingMetadata: spamReportingMetadata,
                    source: source,
                    options: options
                )
            }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration, description: "Update via changes") {
                return GroupsV2Error.timeout
            }.awaitable()
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
                case GroupsV2Error.missingGroupChangeProtos:
                    // If the service returns a group state without change protos,
                    // fail over to the snapshot.
                    return true
                case GroupsV2Error.groupChangeProtoForIncompatibleRevision:
                    // If we got change protos for an incompatible revision,
                    // try and recover using a snapshot.
                    return true
                default:
                    owsFailDebugUnlessNetworkFailure(error)
                    return false
                }
            }()

            guard shouldTrySnapshot else {
                throw error
            }

            // Failover to applying latest snapshot.
            try await Promise.wrapAsync {
                try await self.fetchAndApplyCurrentGroupV2SnapshotFromService(
                    secretParams: secretParams,
                    spamReportingMetadata: spamReportingMetadata,
                    options: options
                )
            }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration, description: "Update via snapshot") {
                return GroupsV2Error.timeout
            }.awaitable()
        }
    }

    private func fetchAndApplyChangeActionsFromService(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        source: GroupChangeActionFetchSource,
        options: TSGroupModelOptions
    ) async throws {
        while true {
            let groupsV2 = SSKEnvironment.shared.groupsV2Ref
            let response = try await groupsV2.fetchSomeGroupChangeActions(
                secretParams: secretParams,
                source: source
            )

            try await self.tryToApplyGroupChangesFromService(
                secretParams: secretParams,
                spamReportingMetadata: spamReportingMetadata,
                groupChanges: response.groupChanges,
                groupSendEndorsementsResponse: response.groupSendEndorsementsResponse,
                options: options
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
        options: TSGroupModelOptions
    ) async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
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
                    transaction: transaction
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
                        transaction: transaction
                    )
                }

                if
                    let applyResult = applyResult,
                    applyResult.wasLocalUserAddedByChange
                {
                    localUserWasAddedBy = applyResult.changeAuthor
                }
            }

            GroupManager.storeProfileKeysFromGroupProtos(
                allProfileKeysByAci: profileKeysByAci,
                authoritativeProfileKeysByAci: authoritativeProfileKeysByAci,
                localIdentifiers: localIdentifiers,
                tx: transaction
            )

            let localUserWasAddedByBlockedUser: Bool
            switch localUserWasAddedBy {
            case nil, .unknown, .localUser:
                localUserWasAddedByBlockedUser = false
            case .legacyE164(let e164):
                localUserWasAddedByBlockedUser = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(
                    .legacyAddress(serviceId: nil, phoneNumber: e164.stringValue),
                    transaction: transaction
                )
            case .aci(let aci):
                localUserWasAddedByBlockedUser = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(
                    .init(aci),
                    transaction: transaction
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
                    tx: transaction
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
                    groupId: groupId.serialize().asData,
                    transaction: transaction
                )
            }

            if let groupSendEndorsementsResponse {
                SSKEnvironment.shared.groupsV2Ref.handleGroupSendEndorsementsResponse(
                    groupSendEndorsementsResponse,
                    groupThreadId: groupThread.sqliteRowId!,
                    secretParams: secretParams,
                    membership: groupThread.groupMembership,
                    localAci: localIdentifiers.aci,
                    tx: transaction.asV2Write
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
        transaction: SDSAnyWriteTransaction
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
            localIdentifiers: localIdentifiers
        )

        var builder = try TSGroupModelBuilder.builderForSnapshot(
            groupV2Snapshot: snapshot,
            transaction: transaction
        )
        builder.apply(options: groupModelOptions)

        let newGroupModel = try builder.buildAsV2()

        let newDisappearingMessageToken = snapshot.disappearingMessageToken
        let didAddLocalUserToV2Group = self.didAddLocalUserToV2Group(
            inGroupChange: firstGroupChange,
            groupV2Params: groupV2Params,
            localIdentifiers: localIdentifiers
        )

        let groupThread = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            didAddLocalUserToV2Group: didAddLocalUserToV2Group,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction
        )

        // NOTE: We don't need to worry about profile keys here.  This method is
        // only used by tryToApplyGroupChangesFromServiceNow() which will take
        // care of that.

        return (
            groupThread,
            addedToNewThreadBy: didAddLocalUserToV2Group ? groupUpdateSource : nil
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
        transaction: SDSAnyWriteTransaction
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
            suffix: "\(oldGroupModel.revision) -> \(groupChange.revision)"
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
                options: options
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

        try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            groupThread: groupThread,
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction
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
        profileKeysByAci.merge(newProfileKeys) { (_, latest) in latest }

        return ApplySingleChangeFromServiceResult(
            changeAuthor: groupUpdateSource,
            wasLocalUserAddedByChange: didAddLocalUserToV2Group(
                inGroupChange: groupChange,
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers
            )
        )
    }

    // MARK: - Current Snapshot

    private func fetchAndApplyCurrentGroupV2SnapshotFromService(
        secretParams: GroupSecretParams,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        options: TSGroupModelOptions
    ) async throws {
        let snapshotResponse = try await SSKEnvironment.shared.groupsV2Ref.fetchLatestSnapshot(groupSecretParams: secretParams)

        let groupV2Snapshot = snapshotResponse.groupSnapshot

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
            let localAci = localIdentifiers.aci

            let profileManager = SSKEnvironment.shared.profileManagerRef
            let localProfileKey = profileManager.localUserProfile(tx: transaction)?.profileKey

            var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot, transaction: transaction)
            builder.apply(options: options)

            if
                let groupId = builder.groupId,
                let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction),
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
            let groupThread = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                newlyLearnedPniToAciAssociations: [:], // Not available from snapshots
                groupUpdateSource: groupUpdateSource,
                didAddLocalUserToV2Group: false,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction
            )

            GroupManager.storeProfileKeysFromGroupProtos(
                allProfileKeysByAci: groupV2Snapshot.profileKeys,
                localIdentifiers: localIdentifiers,
                tx: transaction
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
                    tx: transaction.asV2Write
                )
            }
        }
    }

    private func didAddLocalUserToV2Group(
        inGroupChange groupChange: GroupV2Change,
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers
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
                    uuidCiphertext = try UuidCiphertext(contents: [UInt8](userId))
                } else if let presentationData = action.presentation {
                    let presentation = try ProfileKeyCredentialPresentation(contents: [UInt8](presentationData))
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
                .shouldRetry,
                .timeout,
                .newMemberMissingAnnouncementOnlyCapability:
            return true
        case
                .redundantChange,
                .shouldDiscard,
                .localUserNotInGroup,
                .cannotBuildGroupChangeProto_conflictingChange,
                .cannotBuildGroupChangeProto_lastAdminCantLeaveGroup,
                .cannotBuildGroupChangeProto_tooManyMembers,
                .gv2NotEnabled,
                .localUserIsAlreadyRequestingMember,
                .localUserIsNotARequestingMember,
                .requestingMemberCantLoadGroupState,
                .cantApplyChangesToPlaceholder,
                .expiredGroupInviteLink,
                .groupDoesNotExistOnService,
                .groupNeedsToBeMigrated,
                .groupCannotBeMigrated,
                .groupDowngradeNotAllowed,
                .missingGroupChangeProtos,
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
        localIdentifiers: LocalIdentifiers
    ) throws -> GroupUpdateSource {
        if let changeActionsProto = changeActionsProto {
            return try changeActionsProto.updateSource(
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers
            ).0
        }
        return .unknown
    }
}

public extension GroupsProtoGroupChangeActions {

    func updateSource(
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers
    ) throws -> (GroupUpdateSource, ServiceId?) {
        func compareToLocal(
            source: GroupUpdateSource,
            serviceId: ServiceId
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
                serviceId: aci
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
                    serviceId: pni
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
                    serviceId: firstPromotePniPendingMemberAci
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
                    serviceId: firstPniMemberAddedByLinkAci
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
                    serviceId: firstPniMemberRequestingAddAci
                )
            } else {
                owsFailDebug("Canary: unknown type of PNI-authored group update!")
                return (.unknown, nil)
            }
        }
    }
}
