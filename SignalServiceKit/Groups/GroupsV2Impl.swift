//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class GroupsV2Impl: GroupsV2 {
    private var urlSession: OWSURLSessionProtocol {
        return SSKEnvironment.shared.signalServiceRef.urlSessionForStorageService()
    }

    private let authCredentialStore: AuthCredentialStore
    private let authCredentialManager: any AuthCredentialManager
    private let groupSendEndorsementStore: any GroupSendEndorsementStore

    init(
        appReadiness: AppReadiness,
        authCredentialStore: AuthCredentialStore,
        authCredentialManager: any AuthCredentialManager,
        groupSendEndorsementStore: any GroupSendEndorsementStore,
    ) {
        self.authCredentialStore = authCredentialStore
        self.authCredentialManager = authCredentialManager
        self.groupSendEndorsementStore = groupSendEndorsementStore
        self.profileKeyUpdater = GroupsV2ProfileKeyUpdater(appReadiness: appReadiness)

        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return
            }

            Task {
                do {
                    try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
                } catch {
                    Logger.warn("Local profile update failed with error: \(error)")
                }
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Self.enqueueRestoreGroupPass(authedAccount: .implicit())
        }

        observeNotifications()
    }

    private func refreshGroupWithTimeout(secretParams: GroupSecretParams) async throws {
        do {
            // Ignore the result after the timeout. However, keep refreshing the group
            // in the background since the result is still useful/reusable.
            try await withUncooperativeTimeout(seconds: GroupManager.groupUpdateTimeoutDuration) {
                try await SSKEnvironment.shared.groupV2UpdatesRef.refreshGroup(secretParams: secretParams)
            }
        } catch is UncooperativeTimeoutError {
            throw GroupsV2Error.timeout
        }
    }

    // MARK: - Notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil,
        )
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        Self.enqueueRestoreGroupPass(authedAccount: .implicit())
    }

    @objc
    private func reachabilityChanged() {
        AssertIsOnMainThread()

        Self.enqueueRestoreGroupPass(authedAccount: .implicit())
    }

    @objc
    private func registrationStateDidChange() {
        AssertIsOnMainThread()

        Self.enqueueRestoreGroupPass(authedAccount: .implicit())
    }

    // MARK: - Create Group

    public func createNewGroupOnService(
        _ newGroup: GroupsV2Protos.NewGroupParams,
        downloadedAvatars: GroupAvatarStateMap,
        localAci: Aci,
    ) async throws -> GroupV2SnapshotResponse {
        do {
            return try await _createNewGroupOnService(
                newGroup,
                downloadedAvatars: downloadedAvatars,
                localAci: localAci,
                isRetryingAfterRecoverable400: false,
            )
        } catch GroupsV2Error.serviceRequestHitRecoverable400 {
            // We likely failed to create the group because one of the profile key
            // credentials we submitted was expired, possibly due to drift between our
            // local clock and the service. We should try again exactly once, forcing a
            // refresh of all the credentials first.
            return try await _createNewGroupOnService(
                newGroup,
                downloadedAvatars: downloadedAvatars,
                localAci: localAci,
                isRetryingAfterRecoverable400: true,
            )
        }
    }

    private func _createNewGroupOnService(
        _ newGroup: GroupsV2Protos.NewGroupParams,
        downloadedAvatars: GroupAvatarStateMap,
        localAci: Aci,
        isRetryingAfterRecoverable400: Bool,
    ) async throws -> GroupV2SnapshotResponse {
        let groupProto = try await self.buildProtoToCreateNewGroupOnService(
            newGroup,
            localAci: localAci,
            shouldForceRefreshProfileKeyCredentials: isRetryingAfterRecoverable400,
        )

        let requestBuilder: RequestBuilder = { authCredential -> GroupsV2Request in
            return try StorageService.buildNewGroupRequest(
                groupProto: groupProto,
                groupV2Params: GroupV2Params(groupSecretParams: newGroup.secretParams),
                authCredential: authCredential,
            )
        }

        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: nil,
            behavior400: isRetryingAfterRecoverable400 ? .fail : .reportForRecovery,
            behavior403: .fail,
        )

        let groupResponseProto = try GroupsProtoGroupResponse(serializedData: response.responseBodyData ?? Data())

        return try GroupsV2Protos.parse(
            groupResponseProto: groupResponseProto,
            downloadedAvatars: downloadedAvatars,
            groupV2Params: GroupV2Params(groupSecretParams: newGroup.secretParams),
        )
    }

    /// Construct the proto to create a new group on the service.
    /// - Parameters:
    ///   - shouldForceRefreshProfileKeyCredentials: Whether we should force-refresh PKCs for the group members.
    private func buildProtoToCreateNewGroupOnService(
        _ newGroup: GroupsV2Protos.NewGroupParams,
        localAci: Aci,
        shouldForceRefreshProfileKeyCredentials: Bool,
    ) async throws -> GroupsProtoGroup {
        // Get profile key credentials for everybody who might need them.
        let profileKeyCredentialMap = try await loadProfileKeyCredentials(
            for: [localAci] + newGroup.otherMembers.compactMap({ $0 as? Aci }),
            forceRefresh: shouldForceRefreshProfileKeyCredentials,
        )
        return try GroupsV2Protos.buildNewGroupProto(
            newGroup,
            profileKeyCredentials: profileKeyCredentialMap,
            localAci: localAci,
        )
    }

    // MARK: - Update Group

    // This method updates the group on the service.  This corresponds to:
    //
    // * The local user editing group state (e.g. adding a member).
    // * The local user accepting an invite.
    // * The local user reject an invite.
    // * The local user leaving the group.
    // * etc.
    //
    // Whenever we do this, there's a few follow-on actions that we always want to do (on success):
    //
    // * Update the group in the local database to reflect the update.
    // * Insert "group update info" messages in the conversation history.
    // * Send "group update" messages to other members &  linked devices.
    //
    // We do those things here as well, to DRY them up and to ensure they're always
    // done immediately and in a consistent way.
    private func updateExistingGroupOnService(changes: GroupsV2OutgoingChanges, isDeletingAccount: Bool) async throws -> [Promise<Void>] {

        let justUploadedAvatars = GroupAvatarStateMap.from(changes: changes)
        let groupV2Params = try GroupV2Params(groupSecretParams: changes.groupSecretParams)
        let isAddingOrInviting = changes.membersToAdd.count > 0

        let groupUpdateResult: GroupUpdateResult?
        do {
            groupUpdateResult = try await buildGroupChangeProtoAndTryToUpdateGroupOnService(
                groupV2Params: groupV2Params,
                changes: changes,
            )
        } catch {
            switch error {
            case GroupsV2Error.conflictingChangeOnService:
                // If we failed because a conflicting change has already been
                // committed to the service, we should refresh our local state
                // for the group and try again to apply our changes.

                try await refreshGroupWithTimeout(secretParams: groupV2Params.groupSecretParams)

                groupUpdateResult = try await buildGroupChangeProtoAndTryToUpdateGroupOnService(
                    groupV2Params: groupV2Params,
                    changes: changes,
                )
            case GroupsV2Error.serviceRequestHitRecoverable400:
                // We likely got the 400 because we submitted a proto with
                // profile key credentials and one of them was expired, possibly
                // due to drift between our local clock and the service. We
                // should try again exactly once, forcing a refresh of all the
                // credentials first.

                groupUpdateResult = try await buildGroupChangeProtoAndTryToUpdateGroupOnService(
                    groupV2Params: groupV2Params,
                    changes: changes,
                    shouldForceRefreshProfileKeyCredentials: true,
                    forceFailOn400: true,
                )
            default:
                throw error
            }
        }

        guard let groupUpdateResult else {
            return []
        }

        let changeResponse = try GroupsProtoGroupChangeResponse(serializedData: groupUpdateResult.httpResponse.responseBodyData ?? Data())

        return try await handleGroupUpdatedOnService(
            changeResponse: changeResponse,
            messageBehavior: groupUpdateResult.messageBehavior,
            justUploadedAvatars: justUploadedAvatars,
            isUrgent: isAddingOrInviting,
            isDeletingAccount: isDeletingAccount,
            groupV2Params: groupV2Params,
        )
    }

    private struct GroupUpdateResult {
        var messageBehavior: GroupUpdateMessageBehavior
        var httpResponse: HTTPResponse
    }

    /// Construct a group change proto from the given `changes` for the given
    /// `groupId`, and attempt to commit the group change to the service.
    /// - Parameters:
    ///   - shouldForceRefreshProfileKeyCredentials: Whether we should force-refresh PKCs for any new members while building the proto.
    ///   - forceFailOn400: Whether we should force failure when receiving a 400. If `false`, may instead report expired PKCs.
    private func buildGroupChangeProtoAndTryToUpdateGroupOnService(
        groupV2Params: GroupV2Params,
        changes: GroupsV2OutgoingChanges,
        shouldForceRefreshProfileKeyCredentials: Bool = false,
        forceFailOn400: Bool = false,
    ) async throws -> GroupUpdateResult? {
        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()

        let (groupThread, dmToken) = try SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx) else {
                throw OWSAssertionError("Thread does not exist.")
            }

            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: tx)

            return (groupThread, dmConfiguration.asToken)
        }

        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }

        let builtGroupChange = try await changes.buildGroupChangeProto(
            currentGroupModel: groupModel,
            currentDisappearingMessageToken: dmToken,
            forceRefreshProfileKeyCredentials: shouldForceRefreshProfileKeyCredentials,
        )

        guard let builtGroupChange else {
            return nil
        }

        var behavior400: Behavior400 = .fail
        if
            !forceFailOn400,
            builtGroupChange.proto.containsProfileKeyCredentials
        {
            // If the proto we're submitting contains a profile key credential
            // that's expired, we'll get back a generic 400. Consequently, if
            // we're submitting a proto with PKCs, and we get a 400, we should
            // attempt to recover.

            behavior400 = .reportForRecovery
        }

        let requestBuilder: RequestBuilder = { authCredential in
            return try StorageService.buildUpdateGroupRequest(
                groupChangeProto: builtGroupChange.proto,
                groupV2Params: groupV2Params,
                authCredential: authCredential,
                groupInviteLinkPassword: nil,
            )
        }

        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: behavior400,
            behavior403: .fetchGroupUpdates,
        )

        return GroupUpdateResult(
            messageBehavior: builtGroupChange.groupUpdateMessageBehavior,
            httpResponse: response,
        )
    }

    private func handleGroupUpdatedOnService(
        changeResponse: GroupsProtoGroupChangeResponse,
        messageBehavior: GroupUpdateMessageBehavior,
        justUploadedAvatars: GroupAvatarStateMap,
        isUrgent: Bool,
        isDeletingAccount: Bool,
        groupV2Params: GroupV2Params,
    ) async throws -> [Promise<Void>] {
        guard let changeProto = changeResponse.groupChange else {
            throw OWSAssertionError("Missing groupChange.")
        }
        guard changeProto.changeEpoch <= GroupManager.changeProtoEpoch else {
            throw OWSAssertionError("Invalid embedded change proto epoch: \(changeProto.changeEpoch).")
        }
        let changeActionsProto = try GroupsV2Protos.parseGroupChangeProto(changeProto, verificationOperation: .alreadyTrusted)

        let groupSendEndorsementsResponse = try changeResponse.groupSendEndorsementsResponse.map {
            return try GroupSendEndorsementsResponse(contents: $0)
        }

        try await updateGroupWithChangeActions(
            spamReportingMetadata: .learnedByLocallyInitatedRefresh,
            changeActionsProto: changeActionsProto,
            groupSendEndorsementsResponse: groupSendEndorsementsResponse,
            justUploadedAvatars: justUploadedAvatars,
            groupV2Params: groupV2Params,
        )

        switch messageBehavior {
        case .sendNothing:
            return []
        case .sendUpdateToOtherGroupMembers:
            break
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()
        let groupChangeProtoData = try changeProto.serializedData()

        var sendPromises = [Promise<Void>]()

        sendPromises.append(await GroupManager.sendGroupUpdateMessage(
            groupId: groupId,
            isUrgent: isUrgent,
            isDeletingAccount: isDeletingAccount,
            groupChangeProtoData: groupChangeProtoData,
        ))

        sendPromises.append(contentsOf: await sendGroupUpdateMessageToRemovedUsers(
            changeActionsProto: changeActionsProto,
            groupChangeProtoData: groupChangeProtoData,
            groupV2Params: groupV2Params,
        ))

        return sendPromises
    }

    private func membersRemovedByChangeActions(
        groupChangeActionsProto: GroupsProtoGroupChangeActions,
        groupV2Params: GroupV2Params,
    ) -> [ServiceId] {
        var serviceIds = [ServiceId]()
        for action in groupChangeActionsProto.deleteMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            do {
                serviceIds.append(try groupV2Params.aci(for: userId))
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in groupChangeActionsProto.deletePendingMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            do {
                serviceIds.append(try groupV2Params.serviceId(for: userId))
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in groupChangeActionsProto.deleteRequestingMembers {
            guard let userId = action.deletedUserID else {
                owsFailDebug("Missing userID.")
                continue
            }
            do {
                serviceIds.append(try groupV2Params.aci(for: userId))
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        return serviceIds
    }

    private func sendGroupUpdateMessageToRemovedUsers(
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupChangeProtoData: Data,
        groupV2Params: GroupV2Params,
    ) async -> [Promise<Void>] {
        let serviceIds = membersRemovedByChangeActions(
            groupChangeActionsProto: changeActionsProto,
            groupV2Params: groupV2Params,
        )

        if serviceIds.isEmpty {
            return []
        }

        let plaintextData: Data
        let timestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()
        do {
            let groupV2Context = try GroupsV2Protos.buildGroupContextProto(
                masterKey: groupV2Params.groupSecretParams.getMasterKey(),
                revision: changeActionsProto.revision,
                groupChangeProtoData: groupChangeProtoData,
            )

            let dataBuilder = SSKProtoDataMessage.builder()
            dataBuilder.setGroupV2(groupV2Context)
            dataBuilder.setRequiredProtocolVersion(UInt32(SSKProtoDataMessageProtocolVersion.initial.rawValue))
            dataBuilder.setTimestamp(timestamp)

            let dataProto = try dataBuilder.build()
            let contentBuilder = SSKProtoContent.builder()
            contentBuilder.setDataMessage(dataProto)
            plaintextData = try contentBuilder.buildSerializedData()
        } catch {
            owsFailDebug("\(error)")
            return [Promise(error: error)]
        }

        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            return serviceIds.map { serviceId in
                let address = SignalServiceAddress(serviceId)
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: tx)
                let message = OWSStaticOutgoingMessage(thread: contactThread, timestamp: timestamp, plaintextData: plaintextData, transaction: tx)
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message,
                )
                return SSKEnvironment.shared.messageSenderJobQueueRef.add(.promise, message: preparedMessage, transaction: tx)
            }
        }
    }

    // This method can process protos from another client, so there's a possibility
    // the serverGuid may be present and can be passed along to record with the update.
    public func updateGroupWithChangeActions(
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSecretParams: GroupSecretParams,
    ) async throws {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        try await _updateGroupWithChangeActions(
            spamReportingMetadata: spamReportingMetadata,
            changeActionsProto: changeActionsProto,
            groupSendEndorsementsResponse: nil,
            justUploadedAvatars: nil,
            groupV2Params: groupV2Params,
        )
    }

    private func updateGroupWithChangeActions(
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        justUploadedAvatars: GroupAvatarStateMap?,
        groupV2Params: GroupV2Params,
    ) async throws {
        try await _updateGroupWithChangeActions(
            spamReportingMetadata: spamReportingMetadata,
            changeActionsProto: changeActionsProto,
            groupSendEndorsementsResponse: groupSendEndorsementsResponse,
            justUploadedAvatars: justUploadedAvatars,
            groupV2Params: groupV2Params,
        )
    }

    private func _updateGroupWithChangeActions(
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        changeActionsProto: GroupsProtoGroupChangeActions,
        groupSendEndorsementsResponse: GroupSendEndorsementsResponse?,
        justUploadedAvatars: GroupAvatarStateMap?,
        groupV2Params: GroupV2Params,
    ) async throws {
        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()
        let downloadedAvatars = try await fetchAllAvatarData(
            changeActionsProtos: [changeActionsProto],
            justUploadedAvatars: justUploadedAvatars,
            groupV2Params: groupV2Params,
        )
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            _ = try SSKEnvironment.shared.groupV2UpdatesRef.updateGroupWithChangeActions(
                groupId: groupId,
                spamReportingMetadata: spamReportingMetadata,
                changeActionsProto: changeActionsProto,
                groupSendEndorsementsResponse: groupSendEndorsementsResponse,
                downloadedAvatars: downloadedAvatars,
                transaction: tx,
            )
        }
    }

    // MARK: - Upload Avatar

    public func uploadGroupAvatar(
        avatarData: Data,
        groupSecretParams: GroupSecretParams,
    ) async throws -> String {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        return try await uploadGroupAvatar(avatarData: avatarData, groupV2Params: groupV2Params)
    }

    private func uploadGroupAvatar(
        avatarData: Data,
        groupV2Params: GroupV2Params,
    ) async throws -> String {

        let requestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildGroupAvatarUploadFormRequest(
                groupV2Params: groupV2Params,
                authCredential: authCredential,
            )
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()
        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .fetchGroupUpdates,
        )

        guard let protoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let avatarUploadAttributes = try GroupsProtoAvatarUploadAttributes(serializedData: protoData)
        let uploadForm = try Upload.CDN0.Form.parse(proto: avatarUploadAttributes)
        let encryptedData = try groupV2Params.encryptGroupAvatar(avatarData)
        return try await Upload.CDN0.upload(data: encryptedData, uploadForm: uploadForm)
    }

    // MARK: - Fetch Current Group State

    public func fetchLatestSnapshot(
        secretParams: GroupSecretParams,
        justUploadedAvatars: GroupAvatarStateMap?,
    ) async throws -> GroupV2SnapshotResponse {
        let groupV2Params = try GroupV2Params(groupSecretParams: secretParams)
        return try await fetchLatestSnapshot(groupV2Params: groupV2Params, justUploadedAvatars: justUploadedAvatars)
    }

    private func fetchLatestSnapshot(
        groupV2Params: GroupV2Params,
        justUploadedAvatars: GroupAvatarStateMap?,
    ) async throws -> GroupV2SnapshotResponse {
        let requestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildFetchCurrentGroupV2SnapshotRequest(
                groupV2Params: groupV2Params,
                authCredential: authCredential,
            )
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()
        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .removeFromGroup,
        )

        let groupResponseProto = try GroupsProtoGroupResponse(serializedData: response.responseBodyData ?? Data())

        let downloadedAvatars = try await fetchAllAvatarData(
            groupProtos: [groupResponseProto.group].compacted(),
            justUploadedAvatars: justUploadedAvatars,
            groupV2Params: groupV2Params,
        )

        return try GroupsV2Protos.parse(
            groupResponseProto: groupResponseProto,
            downloadedAvatars: downloadedAvatars,
            groupV2Params: groupV2Params,
        )
    }

    // MARK: - Fetch Group Change Actions

    /// Fetches some group changes (and a snapshot, if needed).
    public func fetchSomeGroupChangeActions(
        secretParams: GroupSecretParams,
        source: GroupChangeActionFetchSource,
    ) async throws -> GroupChangesResponse {
        let groupV2Params = try GroupV2Params(groupSecretParams: secretParams)
        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier().serialize()

        let groupModel: TSGroupModelV2?
        let gseExpiration: UInt64

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        (groupModel, gseExpiration) = databaseStorage.read { tx in
            let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: tx)
            let groupThreadId = groupThread?.sqliteRowId!
            let endorsementRecord = groupThreadId.flatMap({ try? groupSendEndorsementStore.fetchCombinedEndorsement(groupThreadId: $0, tx: tx) })
            return (
                groupThread?.groupModel as? TSGroupModelV2,
                endorsementRecord?.expirationTimestamp ?? 0,
            )
        }

        // If we're fetching because we're processing messages, we can stop as soon
        // as we have a new enough revision. (This can happen due to race
        // conditions receiving messages & refreshing groups, though it generally
        // won't happen because the message processing code only calls this if it
        // believes the revision is too old.)
        if
            let groupModel,
            case .groupMessage(let upThroughRevision) = source,
            groupModel.revision >= upThroughRevision
        {
            // This is fine even if we're a requesting member b/c revision must
            // increment for anything meaningful to happen.
            return GroupChangesResponse(groupChanges: [], shouldFetchMore: false)
        }

        let upThroughRevision: UInt32?
        switch source {
        case .groupMessage(let revision):
            upThroughRevision = revision
        case .other:
            upThroughRevision = nil
        }

        // We can process a change action to move from revision N to revision N + 1
        // UNLESS we have a placeholder group. In that case, we don't actually have
        // revision N -- we have an incomplete copy of revision N that must be made
        // whole before we can apply a delta to it.

        // If we're currently a full member, fetch the next batch.
        if let groupModel, groupModel.groupMembership.isLocalUserFullMember {
            // We're being told about a group we are aware of and are already a member
            // of. In this case, we can figure out which revision we want to start with
            // from local data.
            let startingAtRevision: UInt32
            let includeFirstState: Bool
            switch source {
            case .groupMessage:
                startingAtRevision = groupModel.revision + 1
                includeFirstState = false
            case .other:
                startingAtRevision = groupModel.revision
                includeFirstState = true
            }
            do {
                return try await _fetchSomeGroupChangeActions(
                    secretParams: secretParams,
                    startingAtRevision: startingAtRevision,
                    upThroughRevision: upThroughRevision,
                    includeFirstState: includeFirstState,
                    gseExpiration: gseExpiration,
                )
            } catch GroupsV2Error.localUserNotInGroup {
                // If we can't fetch starting at the next version, we might have been
                // removed and re-added, so we should figure out if we're back in the group
                // at a later revision.
            }
        }

        // Otherwise, we want to figure out where we got permission to start
        // fetching changes, update to that via a snapshot, and then apply
        // everything that follows.
        let startingAtRevision = try await getRevisionLocalUserWasAddedToGroup(secretParams: secretParams)

        return try await _fetchSomeGroupChangeActions(
            secretParams: secretParams,
            startingAtRevision: startingAtRevision,
            upThroughRevision: upThroughRevision,
            includeFirstState: true,
            gseExpiration: gseExpiration,
        )
    }

    private func _fetchSomeGroupChangeActions(
        secretParams: GroupSecretParams,
        startingAtRevision: UInt32,
        upThroughRevision: UInt32?,
        includeFirstState: Bool,
        gseExpiration: UInt64,
    ) async throws -> GroupChangesResponse {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()

        let limit: UInt32? = upThroughRevision.map({ (startingAtRevision <= $0) ? ($0 - startingAtRevision + 1) : 1 })

        let response = try await performServiceRequest(
            requestBuilder: { authCredential in
                return try StorageService.buildFetchGroupChangeActionsRequest(
                    secretParams: secretParams,
                    fromRevision: startingAtRevision,
                    limit: limit,
                    includeFirstState: includeFirstState,
                    gseExpiration: gseExpiration,
                    authCredential: authCredential,
                )
            },
            groupId: groupId,
            behavior400: .fail,
            behavior403: .ignore, // actually means "throw error"
        )
        guard let groupChangesProtoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let earlyEnd: UInt32?
        if response.responseStatusCode == 206 {
            let groupRangeHeader = response.headers["content-range"]
            earlyEnd = try Self.parseEarlyEnd(fromGroupRangeHeader: groupRangeHeader)
        } else {
            earlyEnd = nil
        }
        let groupChangesProto = try GroupsProtoGroupChanges(serializedData: groupChangesProtoData)

        let parsedChanges = try GroupsV2Protos.parseChangesFromService(groupChangesProto: groupChangesProto)
        let downloadedAvatars = try await fetchAllAvatarData(
            groupProtos: parsedChanges.compactMap(\.groupProto),
            changeActionsProtos: parsedChanges.compactMap(\.changeActionsProto),
            groupV2Params: try GroupV2Params(groupSecretParams: secretParams),
        )
        let changes = try parsedChanges.map { parsedChange in
            return GroupV2Change(
                snapshot: try parsedChange.groupProto.map {
                    return try GroupsV2Protos.parse(
                        groupProto: $0,
                        fetchedAlongsideChangeActionsProto: parsedChange.changeActionsProto,
                        downloadedAvatars: downloadedAvatars,
                        groupV2Params: try GroupV2Params(groupSecretParams: secretParams),
                    )
                },
                changeActionsProto: parsedChange.changeActionsProto,
                downloadedAvatars: downloadedAvatars,
            )
        }

        let groupSendEndorsementsResponse = try groupChangesProto.groupSendEndorsementsResponse.map {
            return try GroupSendEndorsementsResponse(contents: $0)
        }

        return GroupChangesResponse(
            groupChanges: changes,
            groupSendEndorsementsResponse: groupSendEndorsementsResponse,
            shouldFetchMore: earlyEnd != nil && (upThroughRevision == nil || upThroughRevision! > earlyEnd!),
        )
    }

    private static func parseEarlyEnd(fromGroupRangeHeader header: String?) throws -> UInt32 {
        guard let header else {
            throw OWSAssertionError("Missing Content-Range for group update request with 206 response")
        }

        let pattern = try! NSRegularExpression(pattern: #"^versions (\d+)-(\d+)/(\d+)$"#)
        guard let match = pattern.firstMatch(in: header, range: header.entireRange) else {
            throw OWSAssertionError("Couldn't parse Content-Range header: \(header)")
        }

        guard let earlyEndRange = Range(match.range(at: 1), in: header) else {
            throw OWSAssertionError("Could not translate NSRange to Range<String.Index>")
        }

        guard let earlyEndValue = UInt32(header[earlyEndRange]) else {
            throw OWSAssertionError("Invalid early-end in Content-Range for group update request: \(header)")
        }

        return earlyEndValue
    }

    private func getRevisionLocalUserWasAddedToGroup(secretParams: GroupSecretParams) async throws -> UInt32 {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        let getJoinedAtRevisionRequestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildGetJoinedAtRevisionRequest(
                secretParams: secretParams,
                authCredential: authCredential,
            )
        }

        // We might get a 403 if we are not a member of the group, e.g. if we are
        // joining via invite link. Passing .ignore means we won't retry and will
        // allow the "not a member" error to be thrown and propagated upwards.
        let response = try await performServiceRequest(
            requestBuilder: getJoinedAtRevisionRequestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .ignore,
        )

        guard let memberData = response.responseBodyData else {
            throw OWSAssertionError("Response missing body data")
        }

        let memberProto = try GroupsProtoMember(serializedData: memberData)

        return memberProto.joinedAtRevision
    }

    // MARK: - Avatar Downloads

    // Before we can apply snapshots/changes from the service, we
    // need to download all avatars they use.  We can skip downloads
    // in a couple of cases:
    //
    // * We just created the group.
    // * We just updated the group and we're applying those changes.
    private func fetchAllAvatarData(
        groupProtos: [GroupsProtoGroup] = [],
        changeActionsProtos: [GroupsProtoGroupChangeActions] = [],
        justUploadedAvatars: GroupAvatarStateMap? = nil,
        groupV2Params: GroupV2Params,
    ) async throws -> GroupAvatarStateMap {

        var downloadedAvatars = GroupAvatarStateMap()

        // Creating or updating a group is a multi-step process
        // that can involve uploading an avatar, updating the
        // group on the service, then updating the local database.
        // We can skip downloading an avatar that we just uploaded
        // using justUploadedAvatars.
        if let justUploadedAvatars {
            downloadedAvatars.merge(justUploadedAvatars)
        }

        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier().serialize()

        // First step - try to skip downloading the current group avatar.
        if
            let groupThread = (SSKEnvironment.shared.databaseStorageRef.read { transaction in
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            }),
            let groupModel = groupThread.groupModel as? TSGroupModelV2
        {
            // Try to add avatar from group model, if any.
            downloadedAvatars.merge(GroupAvatarStateMap.from(groupModel: groupModel))
        }

        let protoAvatarUrlPaths = GroupsV2Protos.collectAvatarUrlPaths(
            groupProtos: groupProtos,
            changeActionsProtos: changeActionsProtos,
        )

        return try await fetchAvatarDataIfNotBlurred(
            avatarUrlPaths: protoAvatarUrlPaths,
            knownAvatarStates: downloadedAvatars,
            groupV2Params: groupV2Params,
        )
    }

    private func fetchAvatarDataIfNotBlurred(
        avatarUrlPaths: [String],
        knownAvatarStates: GroupAvatarStateMap,
        groupV2Params: GroupV2Params,
    ) async throws -> GroupAvatarStateMap {
        let shouldBlurAvatars = try DependenciesBridge.shared.db.read { tx in
            let groupThread = TSGroupThread.fetch(
                forGroupId: try groupV2Params.groupPublicParams.getGroupIdentifier(),
                tx: tx,
            )

            guard let groupThread else {
                return true
            }

            return SSKEnvironment.shared.contactManagerImplRef.shouldBlockAvatarDownload(groupThread: groupThread, tx: tx)
        }

        var downloadedAvatars = knownAvatarStates

        if shouldBlurAvatars {
            let undownloadedAvatarUrlPaths = Set(avatarUrlPaths).subtracting(downloadedAvatars.avatarUrlPaths)
            undownloadedAvatarUrlPaths.forEach { urlPath in
                downloadedAvatars.set(avatarDataState: .lowTrustDownloadWasBlocked, avatarUrlPath: urlPath)
            }
            return downloadedAvatars
        }

        downloadedAvatars.removeBlockedAvatars()
        let undownloadedAvatarUrlPaths = Set(avatarUrlPaths).subtracting(downloadedAvatars.avatarUrlPaths)

        try await withThrowingTaskGroup(of: (String, Data).self) { taskGroup in
            // We need to "populate" any group changes that have a
            // avatar with the avatar data.
            for avatarUrlPath in undownloadedAvatarUrlPaths {
                taskGroup.addTask {
                    var avatarData: Data
                    do {
                        avatarData = try await self.fetchAvatarData(
                            avatarUrlPath: avatarUrlPath,
                            groupV2Params: groupV2Params,
                        )
                    } catch OWSURLSessionError.responseTooLarge {
                        owsFailDebug("Had response-too-large fetching group avatar!")
                        avatarData = Data()
                    } catch where error.httpStatusCode == 404 {
                        // Fulfill with empty data if service returns 404 status code.
                        // We don't want the group to be left in an unrecoverable state
                        // if the avatar is missing from the CDN.
                        owsFailDebug("Had 404 fetching group avatar!")
                        avatarData = Data()
                    }
                    if !avatarData.isEmpty {
                        avatarData = (try? groupV2Params.decryptGroupAvatar(avatarData)) ?? Data()
                    }
                    return (avatarUrlPath, avatarData)
                }
            }

            while let (avatarUrlPath, avatarData) = try await taskGroup.next() {
                let avatarDataState: TSGroupModel.AvatarDataState

                if
                    !avatarData.isEmpty,
                    TSGroupModel.isValidGroupAvatarData(avatarData)
                {
                    avatarDataState = .available(avatarData)
                } else {
                    avatarDataState = .failedToFetchFromCDN
                }

                downloadedAvatars.set(
                    avatarDataState: avatarDataState,
                    avatarUrlPath: avatarUrlPath,
                )
            }
        }

        return downloadedAvatars
    }

    let avatarDownloadQueue = ConcurrentTaskQueue(concurrentLimit: 3)

    private func fetchAvatarData(
        avatarUrlPath: String,
        groupV2Params: GroupV2Params,
    ) async throws -> Data {
        return try await avatarDownloadQueue.run {
            // We throw away decrypted avatars larger than `kMaxEncryptedAvatarSize`.
            return try await GroupsV2AvatarDownloadOperation.run(
                urlPath: avatarUrlPath,
                maxDownloadSize: kMaxEncryptedAvatarSize,
            )
        }
    }

    // MARK: - Generic Group Change

    public func updateGroupV2(
        secretParams: GroupSecretParams,
        isDeletingAccount: Bool,
        changesBlock: (GroupsV2OutgoingChanges) -> Void,
    ) async throws -> [Promise<Void>] {
        let changes = GroupsV2OutgoingChanges(groupSecretParams: secretParams)
        changesBlock(changes)
        return try await updateExistingGroupOnService(changes: changes, isDeletingAccount: isDeletingAccount)
    }

    // MARK: - Rotate Profile Key

    private let profileKeyUpdater: GroupsV2ProfileKeyUpdater

    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: DBWriteTransaction) {
        profileKeyUpdater.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: transaction)
    }

    public func processProfileKeyUpdates() {
        profileKeyUpdater.processProfileKeyUpdates()
    }

    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: DBWriteTransaction) {
        profileKeyUpdater.updateLocalProfileKeyInGroup(groupId: groupId, transaction: transaction)
    }

    // MARK: - Perform Request

    private typealias RequestBuilder = (AuthCredentialWithPni) async throws -> GroupsV2Request

    /// Represents how we should respond to 400 status codes.
    enum Behavior400 {
        case fail
        case reportForRecovery
    }

    /// Represents how we should respond to 403 status codes.
    private enum Behavior403 {
        case fail
        case removeFromGroup
        case fetchGroupUpdates
        case ignore
        case reportInvalidOrBlockedGroupLink
        case localUserIsNotARequestingMember
    }

    /// Make a request to the GV2 service, produced by the given
    /// `requestBuilder`. Specifies how to respond if the request results in
    /// certain errors.
    private func performServiceRequest(
        requestBuilder: RequestBuilder,
        groupId: GroupIdentifier?,
        behavior400: Behavior400,
        behavior403: Behavior403,
    ) async throws -> HTTPResponse {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.httpStatusCode == 401 },
            block: {
                let authCredential = try await authCredentialManager.fetchGroupAuthCredential(localIdentifiers: localIdentifiers)
                let request = try await requestBuilder(authCredential)
                do {
                    return try await performServiceRequestAttempt(request: request)
                } catch {
                    try await self.tryRecoveryFromServiceRequestFailure(
                        error: error,
                        groupId: groupId,
                        behavior400: behavior400,
                        behavior403: behavior403,
                    )
                }
            },
        )
    }

    /// Upon error from performing a service request, attempt to recover based
    /// on the error and our 4XX behaviors.
    private func tryRecoveryFromServiceRequestFailure(
        error: Error,
        groupId: GroupIdentifier?,
        behavior400: Behavior400,
        behavior403: Behavior403,
    ) async throws -> Never {
        // Fall through to retry if retry-able,
        // otherwise reject immediately.
        if let statusCode = error.httpStatusCode {
            switch statusCode {
            case 400:
                switch behavior400 {
                case .fail:
                    owsFailDebug("Unexpected 400.")
                case .reportForRecovery:
                    throw GroupsV2Error.serviceRequestHitRecoverable400
                }

                throw error
            case 401:
                // Retry auth errors after retrieving new temporal credentials.
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    self.authCredentialStore.removeAllGroupAuthCredentials(tx: tx)
                }
                throw error
            case 403:
                guard
                    let responseHeaders = error.httpResponseHeaders,
                    responseHeaders.hasValueForHeader("x-signal-timestamp")
                else {
                    // The cloud infrastructure that sits in front of the Groups
                    // server is known to, in some situations, short-circuit
                    // requests with a 403 before they make it to a Signal
                    // server. That's a problem, since we might take destructive
                    // action locally in response to a 403. 403s from a Signal
                    // server will always contain this header; if we find one
                    // without, we can't trust it and should bail.
                    throw OWSAssertionError("Dropping 403 response without x-signal-timestamp header! \(error)")
                }

                // 403 indicates that we are no longer in the group for
                // many (but not all) group v2 service requests.
                switch behavior403 {
                case .fail:
                    // We should never receive 403 when creating groups.
                    owsFailDebug("Unexpected 403.")

                case .ignore:
                    // We may get a 403 when fetching change actions if
                    // they are not yet a member - for example, if they are
                    // joining via an invite link.
                    owsAssertDebug(groupId != nil, "Expecting a groupId for this path")

                case .removeFromGroup:
                    guard let groupId else {
                        owsFailDebug("GroupId must be set to remove from group")
                        break
                    }
                    // If we receive 403 when trying to fetch group state, we have left the
                    // group, been removed from the group, or had our invite revoked, and we
                    // should make sure group state in the database reflects that.
                    await GroupManager.handleNotInGroup(groupId: groupId)

                case .fetchGroupUpdates:
                    guard let groupId else {
                        owsFailDebug("GroupId must be set to fetch group updates")
                        break
                    }
                    // Service returns 403 if client tries to perform an
                    // update for which it is not authorized (e.g. add a
                    // new member if membership access is admin-only).
                    // The local client can't assume that 403 means they
                    // are not in the group. Therefore we "update group
                    // to latest" to check for and handle that case (see
                    // previous case).
                    self.tryToUpdateGroupToLatest(groupId: groupId)

                case .reportInvalidOrBlockedGroupLink:
                    owsAssertDebug(groupId == nil, "groupId should not be set in this code path.")

                    if error.httpResponseHeaders?.containsBan == true {
                        throw GroupsV2Error.localUserBlockedFromJoining
                    } else {
                        throw GroupsV2Error.expiredGroupInviteLink
                    }

                case .localUserIsNotARequestingMember:
                    owsAssertDebug(groupId == nil, "groupId should not be set in this code path.")
                    throw GroupsV2Error.localUserIsNotARequestingMember
                }

                throw GroupsV2Error.localUserNotInGroup
            case 409:
                // Group update conflict. The caller may be able to recover by
                // retrying, using the change set and the most recent state
                // from the service.
                throw GroupsV2Error.conflictingChangeOnService
            default:
                // Unexpected status code.
                throw error
            }
        } else {
            // Unexpected error.
            throw error
        }
    }

    private func performServiceRequestAttempt(request: GroupsV2Request) async throws -> HTTPResponse {

        let urlSession = self.urlSession

        let requestDescription = "G2 \(request.method) \(request.urlString)"
        Logger.info("Sending… -> \(requestDescription)")

        do {
            let response = try await urlSession.performRequest(
                request.urlString,
                method: request.method,
                headers: request.headers,
                body: request.bodyData,
            )

            let statusCode = response.responseStatusCode
            let hasValidStatusCode = [200, 206].contains(statusCode)
            guard hasValidStatusCode else {
                throw OWSAssertionError("Invalid status code: \(statusCode)")
            }

            // NOTE: responseObject may be nil; not all group v2 responses have bodies.
            Logger.info("HTTP \(statusCode) <- \(requestDescription)")

            return response
        } catch {
            if let statusCode = error.httpStatusCode {
                Logger.warn("HTTP \(statusCode) <- \(requestDescription)")
            } else {
                Logger.warn("Failure. <- \(requestDescription): \(error)")
            }

            if case URLError.cancelled = error {
                throw error
            }

            if error.isNetworkFailureOrTimeout {
                throw error
            }

            // These status codes will be handled by performServiceRequest.
            if let statusCode = error.httpStatusCode, [400, 401, 403, 404, 409].contains(statusCode) {
                throw error
            }

            owsFailDebug("Couldn't send request.")
            throw error
        }
    }

    private func tryToUpdateGroupToLatest(groupId: GroupIdentifier) {
        guard
            let groupThread = (SSKEnvironment.shared.databaseStorageRef.read { transaction in
                TSGroupThread.fetch(forGroupId: groupId, tx: transaction)
            })
        else {
            owsFailDebug("Missing group thread.")
            return
        }
        SSKEnvironment.shared.groupV2UpdatesRef.refreshGroupUpThroughCurrentRevision(groupThread: groupThread, throttle: true)
    }

    // MARK: - GSEs

    public func handleGroupSendEndorsementsResponse(
        _ groupSendEndorsementsResponse: GroupSendEndorsementsResponse,
        groupThreadId: Int64,
        secretParams: GroupSecretParams,
        membership: GroupMembership,
        localAci: Aci,
        tx: DBWriteTransaction,
    ) {
        do {
            let fullMembers = membership.fullMembers.compactMap(\.serviceId)
            let receivedEndorsements = try groupSendEndorsementsResponse.receive(
                groupMembers: fullMembers,
                localUser: localAci,
                groupParams: secretParams,
                serverParams: GroupsV2Protos.serverPublicParams(),
            )
            let combinedEndorsement = receivedEndorsements.combinedEndorsement
            var individualEndorsements = [(ServiceId, GroupSendEndorsement)]()
            for (serviceId, individualEndorsement) in zip(fullMembers, receivedEndorsements.endorsements) {
                if serviceId == localAci {
                    // Don't save our own endorsement. We should never use it.
                    continue
                }
                individualEndorsements.append((serviceId, individualEndorsement))
            }
            let groupId = try secretParams.getPublicParams().getGroupIdentifier()
            Logger.info("Received GSEs that expire at \(groupSendEndorsementsResponse.expiration) for \(groupId)")
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            groupSendEndorsementStore.saveEndorsements(
                groupThreadId: groupThreadId,
                expiration: groupSendEndorsementsResponse.expiration,
                combinedEndorsement: combinedEndorsement,
                individualEndorsements: individualEndorsements.map { serviceId, endorsement in
                    return (recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx).id, endorsement)
                },
                tx: tx,
            )
        } catch {
            owsFailDebug("Couldn't receive GSEs: \(error)")
        }
    }

    // MARK: - ProfileKeyCredentials

    /// Fetches a profile key credential for each passed ACI.
    ///
    /// If credentials aren't available, they are omitted from the result.
    /// (Callers use the absence of a credential to invite a user to a group
    /// rather than adding them directly.)
    ///
    /// If a credential isn't available and the client believes it can fetch it
    /// (i.e., it has a profile key for that user), it will try to do so. If
    /// that fetch fails, this method will re-throw the fetch error.
    ///
    /// - Parameter forceRefresh: If true, a new credential will be fetched for
    /// every element of `acis` for which the client has a believed-to-be-valid
    /// profile key. The result will contain only those new credentials (i.e.,
    /// it will omit credentials for users with missing/incorrect profile keys).
    /// (This handles situations where you have a cached credential the client
    /// believes is valid but the server rejects. If you can't fetch a new
    /// credential for that user, you'll fall back to an invite.)
    public func loadProfileKeyCredentials(
        for acis: [Aci],
        forceRefresh: Bool,
    ) async throws -> [Aci: ExpiringProfileKeyCredential] {
        var results = [Aci: ExpiringProfileKeyCredential]()

        if !forceRefresh {
            results.merge(loadValidProfileKeyCredentials(for: acis), uniquingKeysWith: { _, new in new })
        }

        let profileFetcher = SSKEnvironment.shared.profileFetcherRef

        let fetchedAcis = try await withThrowingTaskGroup(of: Aci?.self) { taskGroup in
            for aciToFetch in Set(acis).subtracting(results.keys) {
                taskGroup.addTask {
                    do {
                        var context = ProfileFetchContext()
                        context.mustFetchNewCredential = true
                        _ = try await profileFetcher.fetchProfile(for: aciToFetch, context: context)
                        return aciToFetch
                    } catch ProfileFetcherError.couldNotFetchCredential {
                        // this is fine
                        return nil
                    }
                }
            }
            return try await taskGroup.reduce(into: [], { $0.append($1) }).compacted()
        }

        if !fetchedAcis.isEmpty {
            results.merge(loadValidProfileKeyCredentials(for: fetchedAcis), uniquingKeysWith: { _, new in new })
        }

        return results
    }

    private func loadValidProfileKeyCredentials(for acis: some Sequence<Aci>) -> [Aci: ExpiringProfileKeyCredential] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return databaseStorage.read { transaction in
            var credentialMap = [Aci: ExpiringProfileKeyCredential]()

            for aci in acis {
                do {
                    if
                        let credential = try SSKEnvironment.shared.versionedProfilesRef.validProfileKeyCredential(
                            for: aci,
                            transaction: transaction,
                        )
                    {
                        credentialMap[aci] = credential
                    }
                } catch {
                    owsFailDebug("Error loading profile key credential: \(error)")
                }
            }

            return credentialMap
        }
    }

    public func hasProfileKeyCredential(
        for aci: Aci,
        transaction: DBReadTransaction,
    ) -> Bool {
        do {
            return try SSKEnvironment.shared.versionedProfilesRef.validProfileKeyCredential(
                for: aci,
                transaction: transaction,
            ) != nil
        } catch let error {
            owsFailDebug("Error getting profile key credential: \(error)")
            return false
        }
    }

    // MARK: - Restore Groups

    public func isGroupKnownToStorageService(
        groupModel: TSGroupModelV2,
        transaction: DBReadTransaction,
    ) -> Bool {
        GroupsV2Impl.isGroupKnownToStorageService(groupModel: groupModel, transaction: transaction)
    }

    public func groupRecordPendingStorageServiceRestore(
        masterKeyData: Data,
        transaction: DBReadTransaction,
    ) -> StorageServiceProtoGroupV2Record? {
        GroupsV2Impl.enqueuedGroupRecordForRestore(masterKeyData: masterKeyData, transaction: transaction)
    }

    public func restoreGroupFromStorageServiceIfNecessary(
        groupRecord: StorageServiceProtoGroupV2Record,
        account: AuthedAccount,
        transaction: DBWriteTransaction,
    ) {
        GroupsV2Impl.enqueueGroupRestore(groupRecord: groupRecord, account: account, transaction: transaction)
    }

    // MARK: - Group Links

    private let groupInviteLinkPreviewCache = LRUCache<Data, GroupInviteLinkPreview>(
        maxSize: 5,
        shouldEvacuateInBackground: true,
    )

    private func groupInviteLinkPreviewCacheKey(groupSecretParams: GroupSecretParams) -> Data {
        return groupSecretParams.serialize()
    }

    public func cachedGroupInviteLinkPreview(groupSecretParams: GroupSecretParams) -> GroupInviteLinkPreview? {
        let cacheKey = groupInviteLinkPreviewCacheKey(groupSecretParams: groupSecretParams)
        return groupInviteLinkPreviewCache.object(forKey: cacheKey)
    }

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    public func fetchGroupInviteLinkPreview(
        inviteLinkPassword: Data?,
        groupSecretParams: GroupSecretParams,
    ) async throws -> GroupInviteLinkPreview {
        let cacheKey = groupInviteLinkPreviewCacheKey(groupSecretParams: groupSecretParams)

        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)

        let requestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildFetchGroupInviteLinkPreviewRequest(
                inviteLinkPassword: inviteLinkPassword,
                groupV2Params: groupV2Params,
                authCredential: authCredential,
            )
        }

        let behavior403: Behavior403 = (
            inviteLinkPassword != nil
                ? .reportInvalidOrBlockedGroupLink
                : .localUserIsNotARequestingMember,
        )
        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: nil,
            behavior400: .fail,
            behavior403: behavior403,
        )
        guard let protoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let groupInviteLinkPreview = try GroupsV2Protos.parseGroupInviteLinkPreview(protoData, groupV2Params: groupV2Params)

        groupInviteLinkPreviewCache.setObject(groupInviteLinkPreview, forKey: cacheKey)

        return groupInviteLinkPreview
    }

    public func fetchGroupInviteLinkPreviewAndRefreshGroup(
        inviteLinkPassword: Data?,
        groupSecretParams: GroupSecretParams,
    ) async throws -> GroupInviteLinkPreview {
        do {
            let groupInviteLinkPreview = try await fetchGroupInviteLinkPreview(inviteLinkPassword: inviteLinkPassword, groupSecretParams: groupSecretParams)
            await updatePlaceholderGroupModelUsingInviteLinkPreview(
                groupSecretParams: groupSecretParams,
                isLocalUserRequestingMember: groupInviteLinkPreview.isLocalUserRequestingMember,
                revision: groupInviteLinkPreview.revision,
            )
            return groupInviteLinkPreview
        } catch {
            if case GroupsV2Error.localUserIsNotARequestingMember = error {
                await self.updatePlaceholderGroupModelUsingInviteLinkPreview(
                    groupSecretParams: groupSecretParams,
                    isLocalUserRequestingMember: false,
                    revision: nil,
                )
            }
            throw error
        }
    }

    public func fetchGroupInviteLinkAvatar(
        avatarUrlPath: String,
        groupSecretParams: GroupSecretParams,
    ) async throws -> Data {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupSecretParams)
        let downloadedAvatars = try await fetchAvatarDataIfNotBlurred(
            avatarUrlPaths: [avatarUrlPath],
            knownAvatarStates: GroupAvatarStateMap(),
            groupV2Params: groupV2Params,
        )

        if let avatarData = downloadedAvatars.avatarDataState(for: avatarUrlPath)!.dataIfPresent {
            return avatarData
        } else {
            throw OWSAssertionError("Unexpectedly missing downloaded avatar data!")
        }
    }

    public func fetchGroupAvatarRestoredFromBackup(
        groupModel: TSGroupModelV2,
        avatarUrlPath: String,
    ) async throws -> TSGroupModel.AvatarDataState {
        let groupV2Params = try GroupV2Params(groupSecretParams: groupModel.secretParams())
        let downloadedAvatars = try await fetchAvatarDataIfNotBlurred(
            avatarUrlPaths: [avatarUrlPath],
            knownAvatarStates: GroupAvatarStateMap(),
            groupV2Params: groupV2Params,
        )

        return downloadedAvatars.avatarDataState(for: avatarUrlPath)!
    }

    public func joinGroupViaInviteLink(
        secretParams: GroupSecretParams,
        inviteLinkPassword: Data,
        downloadedAvatar: (avatarUrlPath: String, avatarData: Data?)?,
    ) async throws {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localAci.")
        }

        try await Retry.performWithBackoff(
            maxAttempts: 5,
            isRetryable: {
                // If multiple people try to join a group at the same time, some of them
                // may encounter HTTP 409 errors. If this happens, we should back off and
                // try again. By also incorporating jitter, multiple clients should be able
                // to avoid each others' requests when retrying.
                //
                // We retry the *entire* operation (are we a member? are we invited? can we
                // join via the invite link?) because HTTP 409 conflicts indicate that the
                // group state has changed, and those changes might add us to the group via
                // some other mechanism.
                if case GroupsV2Error.conflictingChangeOnService = $0 {
                    return true
                }
                return false
            },
            block: {
                try await _joinGroupViaInviteLink(
                    secretParams: secretParams,
                    localIdentifiers: localIdentifiers,
                    inviteLinkPassword: inviteLinkPassword,
                    downloadedAvatar: downloadedAvatar,
                )
            },
        )
    }

    private func _joinGroupViaInviteLink(
        secretParams: GroupSecretParams,
        localIdentifiers: LocalIdentifiers,
        inviteLinkPassword: Data,
        downloadedAvatar: (avatarUrlPath: String, avatarData: Data?)?,
    ) async throws {
        // There are many edge cases around joining groups via invite links.
        //
        // * We might have previously been a member or not.
        // * We might previously have requested to join and been denied.
        // * The group might or might not already exist in the database.
        // * We might already be a full member.
        // * We might already have a pending invite (in which case we should
        //   accept that invite rather than request to join).
        // * The invite link may have been rescinded.

        // Fetch a preview before refreshing the group. If somebody adds us while
        // we're trying to join, this ensures that we run into an HTTP 409 Conflict
        // rather than an HTTP 400. If we fetch a preview after trying to join via
        // "alternate means", then it's possible for us to be added after we try to
        // refresh the group but before we fetch the invite link preview (and, more
        // specifically, its revision). In this case, we may submit a request to
        // join a group that we've already joined.
        let inviteLinkPreview = try await fetchGroupInviteLinkPreview(
            inviteLinkPassword: inviteLinkPassword,
            groupSecretParams: secretParams,
        )

        do {
            // Check if...
            //
            // * We're already in the group.
            // * We already have a pending invite. If so, use it.
            //
            // Note: this will typically fail.
            try await joinGroupViaInviteLinkUsingAlternateMeans(
                secretParams: secretParams,
                localIdentifiers: localIdentifiers,
            )
        } catch GroupsV2Error.localUserNotInGroup {
            try await self.joinGroupViaInviteLinkUsingPatch(
                inviteLinkPreview: inviteLinkPreview,
                inviteLinkPassword: inviteLinkPassword,
                secretParams: secretParams,
                localIdentifiers: localIdentifiers,
                downloadedAvatar: downloadedAvatar,
            )
        }
    }

    private func joinGroupViaInviteLinkUsingAlternateMeans(
        secretParams: GroupSecretParams,
        localIdentifiers: LocalIdentifiers,
    ) async throws {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()

        // First try to fetch latest group state from service.
        // This will fail for users trying to join via group link
        // who are not yet in the group.
        try await refreshGroupWithTimeout(secretParams: secretParams)

        let groupThread = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return TSGroupThread.fetch(forGroupId: groupId, tx: tx)
        }
        guard let groupModelV2 = groupThread?.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }
        let groupMembership = groupModelV2.groupMembership
        if groupMembership.isFullMember(localIdentifiers.aci) || groupMembership.isRequestingMember(localIdentifiers.aci) {
            // We're already in the group.
            return
        }
        if groupMembership.isInvitedMember(localIdentifiers.aci) {
            // We're already invited by ACI; try to join by accepting the invite.
            // That will make us a full member; requesting to join via
            // the invite link might make us a requesting member.
            try await GroupManager.localAcceptInviteToGroupV2(groupModel: groupModelV2)
            return
        }
        if let pni = localIdentifiers.pni, groupMembership.isInvitedMember(pni) {
            // We're already invited by PNI; try to join by accepting the invite.
            // That will make us a full member; requesting to join via
            // the invite link might make us a requesting member.
            try await GroupManager.localAcceptInviteToGroupV2(groupModel: groupModelV2)
            return
        }
        throw GroupsV2Error.localUserNotInGroup
    }

    private func joinGroupViaInviteLinkUsingPatch(
        inviteLinkPreview: GroupInviteLinkPreview,
        inviteLinkPassword: Data,
        secretParams: GroupSecretParams,
        localIdentifiers: LocalIdentifiers,
        downloadedAvatar: (avatarUrlPath: String, avatarData: Data?)?,
    ) async throws {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()

        let revisionForPlaceholderModel: UInt32
        if inviteLinkPreview.isLocalUserRequestingMember {
            // Use the current revision when creating a placeholder group.
            revisionForPlaceholderModel = inviteLinkPreview.revision
        } else {
            let joinMode: GroupLinkJoinMode
            switch inviteLinkPreview.addFromInviteLinkAccess {
            case .any:
                joinMode = .asMember
            case .administrator:
                joinMode = .asRequestingMember
            default:
                throw OWSAssertionError("Invalid addFromInviteLinkAccess.")
            }
            let groupChangeProto = try await self.buildChangeActionsProtoToJoinGroupLink(
                newRevision: inviteLinkPreview.revision + 1,
                joinMode: joinMode,
                secretParams: secretParams,
                localIdentifiers: localIdentifiers,
            )
            let requestBuilder: RequestBuilder = { authCredential in
                return try StorageService.buildUpdateGroupRequest(
                    groupChangeProto: groupChangeProto,
                    groupV2Params: try GroupV2Params(groupSecretParams: secretParams),
                    authCredential: authCredential,
                    groupInviteLinkPassword: inviteLinkPassword,
                )
            }
            let response = try await performServiceRequest(
                requestBuilder: requestBuilder,
                groupId: groupId,
                behavior400: .fail,
                behavior403: .reportInvalidOrBlockedGroupLink,
            )

            let changeResponse = try GroupsProtoGroupChangeResponse(serializedData: response.responseBodyData ?? Data())

            guard let changeProto = changeResponse.groupChange else {
                throw OWSAssertionError("Missing groupChange after updating group.")
            }

            switch joinMode {
            case .asMember:
                // The PATCH request that adds us to the group (as a full or requesting member)
                // only return the "change actions" proto data, but not a full snapshot
                // so we need to separately GET the latest group state and update the database.
                //
                // Download and update database with the group state.
                try await SSKEnvironment.shared.groupV2UpdatesRef.refreshGroup(
                    secretParams: secretParams,
                    options: [.didJustAddSelfViaGroupLink],
                )
                _ = await GroupManager.sendGroupUpdateMessage(
                    groupId: groupId,
                    groupChangeProtoData: try changeProto.serializedData(),
                )
                return
            case .asRequestingMember:
                revisionForPlaceholderModel = groupChangeProto.revision
            }
        }

        // We create a placeholder in a couple of different scenarios:
        //
        // * The GroupInviteLinkPreview indicates that we are already a requesting
        // member of the group but the group does not yet exist in the database.
        //
        // * We successfully request to join a group via group invite link.
        // Afterward we do not have access to group state on the service.

        try await createPlaceholderGroupForJoinRequest(
            inviteLinkPassword: inviteLinkPassword,
            secretParams: secretParams,
            localIdentifiers: localIdentifiers,
            inviteLinkPreview: inviteLinkPreview,
            downloadedAvatar: downloadedAvatar,
            revisionForPlaceholderModel: revisionForPlaceholderModel,
        )
    }

    private func createPlaceholderGroupForJoinRequest(
        inviteLinkPassword: Data,
        secretParams: GroupSecretParams,
        localIdentifiers: LocalIdentifiers,
        inviteLinkPreview: GroupInviteLinkPreview,
        downloadedAvatar: (avatarUrlPath: String, avatarData: Data?)?,
        revisionForPlaceholderModel revision: UInt32,
    ) async throws {
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()

        let avatarUrlPath = inviteLinkPreview.avatarUrlPath
        let avatarData: Data?
        if let avatarUrlPath {
            if let downloadedAvatar, downloadedAvatar.avatarUrlPath == avatarUrlPath {
                avatarData = downloadedAvatar.avatarData
            } else {
                // We might fail to download the avatar. That's fine; this is just a
                // placeholder model.
                avatarData = try? await self.fetchGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath, groupSecretParams: secretParams)
            }
        } else {
            avatarData = nil
        }

        // We might be creating a placeholder for a revision that we just
        // created or for one we learned about from a GroupInviteLinkPreview.
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction throws -> Void in
            if let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction) {
                // The group already existing in the database; make sure
                // that we are a requesting member.
                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                let oldGroupMembership = oldGroupModel.groupMembership
                if oldGroupModel.revision >= revision, oldGroupMembership.isRequestingMember(localIdentifiers.aci) {
                    // No need to update database, group state is already acceptable.
                    return
                }
                var builder = oldGroupModel.asBuilder
                builder.isJoinRequestPlaceholder = true
                builder.groupV2Revision = max(revision, oldGroupModel.revision)
                var membershipBuilder = oldGroupMembership.asBuilder
                membershipBuilder.remove(localIdentifiers.aci)
                membershipBuilder.addRequestingMember(localIdentifiers.aci)
                builder.groupMembership = membershipBuilder.build()
                let newGroupModel = try builder.build()

                groupThread.update(with: newGroupModel, transaction: transaction)

                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction).asToken
                GroupManager.insertGroupUpdateInfoMessage(
                    groupThread: groupThread,
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel,
                    oldDisappearingMessageToken: dmToken,
                    newDisappearingMessageToken: dmToken,
                    newlyLearnedPniToAciAssociations: [:],
                    groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    transaction: transaction,
                )
            } else {
                // Create a placeholder group.
                var builder = TSGroupModelBuilder(secretParams: secretParams)
                builder.name = inviteLinkPreview.title
                builder.descriptionText = inviteLinkPreview.descriptionText
                builder.groupAccess = GroupAccess(
                    members: GroupAccess.defaultForV2.members,
                    attributes: GroupAccess.defaultForV2.attributes,
                    addFromInviteLink: inviteLinkPreview.addFromInviteLinkAccess,
                )
                builder.groupV2Revision = revision
                builder.inviteLinkPassword = inviteLinkPassword
                builder.isJoinRequestPlaceholder = true
                builder.avatarUrlPath = inviteLinkPreview.avatarUrlPath
                builder.avatarDataState = TSGroupModel.AvatarDataState(avatarData: avatarData)

                var membershipBuilder = GroupMembership.Builder()
                membershipBuilder.addRequestingMember(localIdentifiers.aci)
                builder.groupMembership = membershipBuilder.build()

                let groupModel = try builder.buildAsV2()
                let groupThread = DependenciesBridge.shared.threadStore.createGroupThread(
                    groupModel: groupModel,
                    tx: transaction,
                )

                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction).asToken
                GroupManager.insertGroupUpdateInfoMessageForNewGroup(
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    groupThread: groupThread,
                    groupModel: groupModel,
                    disappearingMessageToken: dmToken,
                    groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                    transaction: transaction,
                )
            }
        }
    }

    private enum GroupLinkJoinMode {
        case asMember
        case asRequestingMember
    }

    private func buildChangeActionsProtoToJoinGroupLink(
        newRevision: UInt32,
        joinMode: GroupLinkJoinMode,
        secretParams: GroupSecretParams,
        localIdentifiers: LocalIdentifiers,
    ) async throws -> GroupsProtoGroupChangeActions {
        let localAci = localIdentifiers.aci

        let profileKeyCredentialMap = try await loadProfileKeyCredentials(for: [localAci], forceRefresh: false)

        guard let localProfileKeyCredential = profileKeyCredentialMap[localAci] else {
            throw OWSAssertionError("Missing localProfileKeyCredential.")
        }

        var actionsBuilder = GroupsProtoGroupChangeActions.builder()

        actionsBuilder.setRevision(newRevision)

        switch joinMode {
        case .asMember:
            let role = TSGroupMemberRole.`normal`
            var actionBuilder = GroupsProtoGroupChangeActionsAddMemberAction.builder()
            actionBuilder.setAdded(
                try GroupsV2Protos.buildMemberProto(
                    profileKeyCredential: localProfileKeyCredential,
                    role: role.asProtoRole,
                    groupV2Params: try GroupV2Params(groupSecretParams: secretParams),
                ))
            actionsBuilder.addAddMembers(actionBuilder.buildInfallibly())
        case .asRequestingMember:
            var actionBuilder = GroupsProtoGroupChangeActionsAddRequestingMemberAction.builder()
            actionBuilder.setAdded(
                try GroupsV2Protos.buildRequestingMemberProto(
                    profileKeyCredential: localProfileKeyCredential,
                    groupV2Params: try GroupV2Params(groupSecretParams: secretParams),
                ))
            actionsBuilder.addAddRequestingMembers(actionBuilder.buildInfallibly())
        }

        return actionsBuilder.buildInfallibly()
    }

    public func cancelRequestToJoin(groupModel: TSGroupModelV2) async throws {
        let groupV2Params = try groupModel.groupV2Params()

        var newRevision: UInt32?
        do {
            newRevision = try await cancelRequestToJoinUsingPatch(groupV2Params: groupV2Params)
        } catch {
            switch error {
            case GroupsV2Error.localUserIsNotARequestingMember:
                // In both of these cases, our request has already been removed. We can proceed with updating the model.
                break
            default:
                // Otherwise, we don't recover and let the error propogate
                throw error
            }
        }

        try await updateGroupRemovingMemberRequest(groupId: groupModel.groupId, newRevision: newRevision)
    }

    private func updateGroupRemovingMemberRequest(
        groupId: Data,
        newRevision proposedRevision: UInt32?,
    ) async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction -> Void in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing groupThread.")
            }
            // The group already existing in the database; make sure
            // that we are a requesting member.
            guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid groupModel.")
            }
            let oldGroupMembership = oldGroupModel.groupMembership
            var newRevision = oldGroupModel.revision + 1
            if let proposedRevision {
                if oldGroupModel.revision >= proposedRevision {
                    // No need to update database, group state is already acceptable.
                    return
                }
                newRevision = proposedRevision
            }

            var builder = oldGroupModel.asBuilder
            builder.isJoinRequestPlaceholder = true
            builder.groupV2Revision = newRevision

            var membershipBuilder = oldGroupMembership.asBuilder
            membershipBuilder.remove(localIdentifiers.aci)
            builder.groupMembership = membershipBuilder.build()
            let newGroupModel = try builder.build()

            groupThread.update(with: newGroupModel, transaction: transaction)

            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction).asToken
            GroupManager.insertGroupUpdateInfoMessage(
                groupThread: groupThread,
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel,
                oldDisappearingMessageToken: dmToken,
                newDisappearingMessageToken: dmToken,
                newlyLearnedPniToAciAssociations: [:],
                groupUpdateSource: .localUser(originalSource: .aci(localIdentifiers.aci)),
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: .createdByLocalAction,
                transaction: transaction,
            )
        }
    }

    private func cancelRequestToJoinUsingPatch(groupV2Params: GroupV2Params) async throws -> UInt32 {
        let groupId = try groupV2Params.groupPublicParams.getGroupIdentifier()

        // We re-fetch the GroupInviteLinkPreview before trying in order to get the latest:
        //
        // * revision
        // * addFromInviteLinkAccess
        // * local user's request status.
        let groupInviteLinkPreview = try await fetchGroupInviteLinkPreview(
            inviteLinkPassword: nil,
            groupSecretParams: groupV2Params.groupSecretParams,
        )
        let oldRevision = groupInviteLinkPreview.revision
        let newRevision = oldRevision + 1

        let requestBuilder: RequestBuilder = { authCredential in
            let groupChangeProto = try self.buildChangeActionsProtoToCancelMemberRequest(
                groupV2Params: groupV2Params,
                newRevision: newRevision,
            )
            return try StorageService.buildUpdateGroupRequest(
                groupChangeProto: groupChangeProto,
                groupV2Params: groupV2Params,
                authCredential: authCredential,
                groupInviteLinkPassword: nil,
            )
        }

        _ = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: groupId,
            behavior400: .fail,
            behavior403: .fail,
        )

        return newRevision
    }

    private func buildChangeActionsProtoToCancelMemberRequest(
        groupV2Params: GroupV2Params,
        newRevision: UInt32,
    ) throws -> GroupsProtoGroupChangeActions {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            throw OWSAssertionError("Missing localAci.")
        }

        var actionsBuilder = GroupsProtoGroupChangeActions.builder()
        actionsBuilder.setRevision(newRevision)

        var actionBuilder = GroupsProtoGroupChangeActionsDeleteRequestingMemberAction.builder()
        let userId = try groupV2Params.userId(for: localAci)
        actionBuilder.setDeletedUserID(userId)
        actionsBuilder.addDeleteRequestingMembers(actionBuilder.buildInfallibly())

        return actionsBuilder.buildInfallibly()
    }

    private func updatePlaceholderGroupModelUsingInviteLinkPreview(
        groupSecretParams: GroupSecretParams,
        isLocalUserRequestingMember: Bool,
        revision: UInt32?,
    ) async {
        do {
            let groupId = try groupSecretParams.getPublicParams().getGroupIdentifier()
            try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction) else {
                    throw OWSAssertionError("Missing localIdentifiers.")
                }
                guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction) else {
                    // Thread not yet in database.
                    return
                }
                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid groupModel.")
                }
                guard oldGroupModel.isJoinRequestPlaceholder else {
                    // Not a placeholder model; no need to update.
                    return
                }
                let oldGroupMembership = oldGroupModel.groupMembership
                guard isLocalUserRequestingMember != oldGroupMembership.isLocalUserRequestingMember else {
                    // Nothing to change.
                    return
                }
                var builder = oldGroupModel.asBuilder
                builder.isJoinRequestPlaceholder = true
                if let revision {
                    builder.groupV2Revision = max(revision, builder.groupV2Revision)
                }

                var membershipBuilder = oldGroupMembership.asBuilder
                membershipBuilder.remove(localIdentifiers.aci)
                if isLocalUserRequestingMember {
                    membershipBuilder.addRequestingMember(localIdentifiers.aci)
                }
                builder.groupMembership = membershipBuilder.build()
                let newGroupModel = try builder.build()

                groupThread.update(with: newGroupModel, transaction: transaction)

                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmToken = dmConfigurationStore.fetchOrBuildDefault(for: .thread(groupThread), tx: transaction).asToken
                // groupUpdateSource is unknown; we don't know who did the update.
                GroupManager.insertGroupUpdateInfoMessage(
                    groupThread: groupThread,
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel,
                    oldDisappearingMessageToken: dmToken,
                    newDisappearingMessageToken: dmToken,
                    newlyLearnedPniToAciAssociations: [:],
                    groupUpdateSource: .unknown,
                    localIdentifiers: localIdentifiers,
                    spamReportingMetadata: .createdByLocalAction,
                    transaction: transaction,
                )
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    public func fetchGroupExternalCredentials(secretParams: GroupSecretParams) async throws -> GroupsProtoGroupExternalCredential {
        let groupParams = try GroupV2Params(groupSecretParams: secretParams)

        let requestBuilder: RequestBuilder = { authCredential in
            try StorageService.buildFetchGroupExternalCredentials(
                groupV2Params: groupParams,
                authCredential: authCredential,
            )
        }

        let response = try await performServiceRequest(
            requestBuilder: requestBuilder,
            groupId: try secretParams.getPublicParams().getGroupIdentifier(),
            behavior400: .fail,
            behavior403: .fetchGroupUpdates,
        )

        guard let groupProtoData = response.responseBodyData else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        return try GroupsProtoGroupExternalCredential(serializedData: groupProtoData)
    }
}

private extension HttpHeaders {
    private static let forbiddenKey: String = "X-Signal-Forbidden-Reason"
    private static let forbiddenValue: String = "banned"

    var containsBan: Bool {
        value(forHeader: Self.forbiddenKey) == Self.forbiddenValue
    }
}

// MARK: - What's in the change actions?

private extension GroupsProtoGroupChangeActions {
    var containsProfileKeyCredentials: Bool {
        // When adding a member, we include their profile key credential.
        let isAddingMembers = !addMembers.isEmpty

        // When promoting an invited member, we include the profile key for
        // their ACI.
        // Note: in practice the only user we'll promote is ourself, when
        // accepting an invite.
        let isPromotingPni = !promotePniPendingMembers.isEmpty
        let isPromotingAci = !promotePendingMembers.isEmpty

        return isAddingMembers || isPromotingPni || isPromotingAci
    }
}
