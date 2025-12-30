//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

private struct IncomingGroupsV2MessageJobInfo {
    let job: GroupMessageProcessorJob
    let envelope: SSKProtoEnvelope
    let plaintextData: Data
    let groupContext: SSKProtoGroupContextV2
    let groupContextInfo: GroupV2ContextInfo
}

// MARK: -

/// Processes group messages for a single group.
///
/// * It retries with exponential backoff.
/// * It retries immediately if reachability, etc., change.
///
/// It returns when all jobs are processed.
class SpecificGroupMessageProcessor {
    fileprivate let groupId: Data
    private let finder = GroupMessageProcessorJobStore()

    fileprivate init(groupId: Data) {
        self.groupId = groupId

        observeNotifications()
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(chatConnectionStateDidChange),
            name: OWSChatConnection.chatConnectionStateDidChange,
            object: nil,
        )
        nc.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil,
        )
    }

    // MARK: - Notifications

    @objc
    @MainActor
    private func chatConnectionStateDidChange() {
        AssertIsOnMainThread()
        setMightBeAbleToMakeProgress()
    }

    @objc
    @MainActor
    private func reachabilityChanged() {
        AssertIsOnMainThread()
        setMightBeAbleToMakeProgress()
    }

    // MARK: -

    /// Trigger an immediate retry of queued jobs.
    ///
    /// Call this when an external trigger (e.g., "network became reachable")
    /// indicates that previously-failed jobs may succeed upon another attempt.
    private func setMightBeAbleToMakeProgress() {
        state.update {
            $0.mightBeAbleToMakeProgress = true
            // If we're currently waiting, try again immediately.
            $0.retryIntervalTask?.cancel()
        }
    }

    private struct State {
        var mightBeAbleToMakeProgress = true
        var retryIntervalTask: Task<Void, any Error>?
    }

    private let state = AtomicValue(State(), lock: .init())

    func processBatches(willFetchNextJobs: () -> Void) async {
        var backoffCount = 0
        // For as long as there are jobs to process...
        while true {
            let backgroundTask = OWSBackgroundTask(label: "\(#function)")
            do throws(RetryableError) {
                defer { backgroundTask.end() }

                var newestGuaranteedFailureJobId: Int64?

                // ...process them, until we hit an error that requires backoff.
                while true {
                    do throws(CancellationError) {
                        try await Preconditions([
                            ProcessingPermittedPrecondition(messagePipelineSupervisor: SSKEnvironment.shared.messagePipelineSupervisorRef),
                            NotificationPrecondition(notificationName: .registrationStateDidChange, isSatisfied: {
                                return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
                            }),
                        ]).waitUntilSatisfied()
                    } catch {
                        owsFail("Cancellation isn't supported.")
                    }

                    // We want a value that is just high enough to yield perf benefits.
                    let kIncomingMessageBatchSize: Int = 16
                    // If the app is in the background, use batch size of 1. This (only
                    // slightly) makes it less likely that we'll hit a 0xdead10cc crash and
                    // need to re-do work we've already done.
                    // TODO: Stop processing batches when suspending.
                    let batchSize: Int = CurrentAppContext().isInBackground() ? 1 : kIncomingMessageBatchSize

                    willFetchNextJobs()

                    // Keep track of external triggers while we're processing a batch. These
                    // may indicate that immediate retries are worthwhile.
                    state.update {
                        $0.mightBeAbleToMakeProgress = false
                    }

                    let hasMore = try await self.processBatch(
                        batchLimit: batchSize,
                        newestGuaranteedFailureJobId: &newestGuaranteedFailureJobId,
                    )
                    if !hasMore {
                        return
                    }

                    // If we successfully process a batch, reset the backoff counter. If we had
                    // to back off while processing a specific update, the next update
                    // shouldn't reuse that backoff because things seem to be back to normal.
                    backoffCount = 0
                }
            } catch let error {
                Logger.warn("\(error)")

                let retryIntervalTask = state.update { mutableState -> Task<Void, any Error>? in
                    if mutableState.mightBeAbleToMakeProgress {
                        Logger.info("Retrying immediately because of an external trigger.")
                        return nil
                    } else {
                        let retryIntervalNs = OWSOperation.retryIntervalForExponentialBackoff(failureCount: backoffCount).clampedNanoseconds
                        Logger.warn("Waiting for \(OWSOperation.formattedNs(retryIntervalNs))s before retrying.")
                        let retryIntervalTask = Task {
                            try await Task.sleep(nanoseconds: retryIntervalNs)
                        }
                        mutableState.retryIntervalTask = retryIntervalTask
                        return retryIntervalTask
                    }
                }

                do {
                    if let retryIntervalTask {
                        try await retryIntervalTask.value
                        // Don't increment backoffCount until after we wait for the entire backoff
                        // to elapse. This ensures that repeated failures (i.e., hitting the server
                        // and getting errors) will exponentially back off, but if an external
                        // trigger flip-flops repeatedly (i.e., turning Airplane Mode on and off),
                        // we increment the exponential backoff to an absurd level.
                        backoffCount += 1
                    }
                } catch {
                    Logger.info("Waking up & retrying immediately because of an external trigger.")
                }
            }
        }
    }

    private static func jobInfo(forJob job: GroupMessageProcessorJob) -> IncomingGroupsV2MessageJobInfo? {
        guard let envelope = try? job.parseEnvelope() else {
            owsFailDebug("Missing envelope.")
            return nil
        }
        guard
            let plaintextData = job.plaintextData,
            let groupContext = GroupMessageProcessorManager.groupContextV2(fromPlaintextData: plaintextData)
        else {
            owsFailDebug("Missing group context.")
            return nil
        }
        guard groupContext.hasRevision else {
            owsFailDebug("Missing revision.")
            return nil
        }
        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupContext.masterKey ?? Data())
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return nil
        }
        return IncomingGroupsV2MessageJobInfo(
            job: job,
            envelope: envelope,
            plaintextData: plaintextData,
            groupContext: groupContext,
            groupContextInfo: groupContextInfo,
        )
    }

    static func discardMode(
        forMessageFrom sourceAci: Aci,
        groupContext: SSKProtoGroupContextV2,
        tx: DBReadTransaction,
    ) -> GroupMessageProcessorManager.DiscardMode {
        guard groupContext.hasRevision else {
            Logger.info("Missing revision in group context")
            return .discard
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupContext.masterKey ?? Data())
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return .discard
        }

        return GroupMessageProcessorManager.discardMode(
            forMessageFrom: sourceAci,
            groupId: groupContextInfo.groupId,
            tx: tx,
        )
    }

    private static func discardMode(
        forJobInfo jobInfo: IncomingGroupsV2MessageJobInfo,
        hasGroupBeenUpdated: Bool,
        tx: DBReadTransaction,
    ) -> GroupMessageProcessorManager.DiscardMode {
        guard
            let sourceAci = Aci.parseFrom(
                serviceIdBinary: jobInfo.envelope.sourceServiceIDBinary,
                serviceIdString: jobInfo.envelope.sourceServiceID,
            )
        else {
            owsFailDebug("Invalid source address.")
            return .discard
        }
        return GroupMessageProcessorManager.discardMode(
            forMessageFrom: sourceAci,
            groupId: jobInfo.groupContextInfo.groupId,
            shouldCheckGroupModel: hasGroupBeenUpdated,
            tx: tx,
        )
    }

    /// As in other message receiving flows, we want to do batch processing
    /// wherever possible for perf reasons (to reduce view updates). We should
    /// be able to mostly do that. However, in some cases we need to update the
    /// group before we can process the message. These messages may require
    /// network requests, so they aren't batched with other messages.
    private func canJobBeProcessedWithoutUpdate(
        jobInfo: IncomingGroupsV2MessageJobInfo,
        tx: DBReadTransaction,
    ) -> Bool {
        if .discard == Self.discardMode(forJobInfo: jobInfo, hasGroupBeenUpdated: false, tx: tx) {
            return true
        }
        return GroupMessageProcessorManager.canContextBeProcessedWithoutUpdate(
            groupContext: jobInfo.groupContext,
            groupContextInfo: jobInfo.groupContextInfo,
            tx: tx,
        )
    }

    /// This method may process only a subset of the jobs.
    ///
    /// - Returns: True if there are more jobs to process.
    private func processBatch(batchLimit: Int, newestGuaranteedFailureJobId: inout Int64?) async throws(RetryableError) -> Bool {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        let hasMore: Bool
        let asyncJob: IncomingGroupsV2MessageJobInfo?

        (hasMore, asyncJob) = await databaseStorage.awaitableWrite { tx -> (Bool, IncomingGroupsV2MessageJobInfo?) in
            for _ in 1...batchLimit {
                guard let job = self.nextJob(tx: tx) else {
                    // Either there's no more jobs or we couldn't fetch jobs. Stop trying.
                    return (false, nil)
                }
                guard let jobInfo = Self.jobInfo(forJob: job) else {
                    self.didCompleteJob(job, tx: tx)
                    continue
                }
                if self.canJobBeProcessedWithoutUpdate(jobInfo: jobInfo, tx: tx) {
                    self.performLocalProcessingSync(jobInfo: jobInfo, tx: tx)
                    self.didCompleteJob(job, tx: tx)
                    continue
                }
                return (true, jobInfo)
            }
            return (true, nil)
        }

        if let asyncJob {
            let didUpdateGroup = try await updateGroup(
                jobInfo: asyncJob,
                newestGuaranteedFailureJobId: &newestGuaranteedFailureJobId,
            )
            await databaseStorage.awaitableWrite { tx in
                if didUpdateGroup {
                    self.performLocalProcessingSync(jobInfo: asyncJob, tx: tx)
                } else {
                    // This only happens for terminal errors when updating the group via the
                    // service. That should only happen if we can no longer access the group
                    // state, e.g. a) we were kicked out of the group, b) our invite was
                    // revoked, or c) our request to join via group invite link was denied.
                    Logger.warn("Discarding unprocess-able message \(asyncJob.envelope.timestamp)")
                }
                self.didCompleteJob(asyncJob.job, tx: tx)
            }
        }

        return hasMore
    }

    private func nextJob(tx: DBReadTransaction) -> GroupMessageProcessorJob? {
        return finder.nextJob(forGroupId: self.groupId, tx: tx)
    }

    private func newestJobId() -> Int64? {
        let db = DependenciesBridge.shared.db
        return db.read { tx in
            finder.newestJobId(tx: tx)
        }
    }

    private func didCompleteJob(_ job: GroupMessageProcessorJob, tx: DBWriteTransaction) {
        finder.removeJob(withRowId: job.id, tx: tx)
    }

    private func performLocalProcessingSync(
        jobInfo: IncomingGroupsV2MessageJobInfo,
        tx: DBWriteTransaction,
    ) {
        let discardMode = Self.discardMode(forJobInfo: jobInfo, hasGroupBeenUpdated: true, tx: tx)
        switch discardMode {
        case .discard:
            // Do nothing.
            break
        case .doNotDiscard, .discardVisibleMessages:
            SSKEnvironment.shared.messageReceiverRef.processEnvelope(
                jobInfo.envelope,
                plaintextData: jobInfo.plaintextData,
                wasReceivedByUD: jobInfo.job.wasReceivedByUD,
                serverDeliveryTimestamp: jobInfo.job.serverDeliveryTimestamp,
                shouldDiscardVisibleMessages: discardMode == .discardVisibleMessages,
                localIdentifiers: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)!,
                tx: tx,
            )
        }
    }

    private func updateGroup(
        jobInfo: IncomingGroupsV2MessageJobInfo,
        newestGuaranteedFailureJobId: inout Int64?,
    ) async throws(RetryableError) -> Bool {
        // First, we try to update the group locally using changes embedded in
        // the group context (if any).
        if try await updateUsingEmbeddedGroupUpdate(jobInfo: jobInfo) {
            return true
        }

        // Next, we check if we've already failed to fetch state from the server.
        // If we've hit a terminal error, that error applies to ALL of the
        // already-enqueued messages. (It doesn't apply to newly-enqueued messages,
        // though, which is why we compare the job's ID.)
        if let newestGuaranteedFailureJobId, jobInfo.job.id <= newestGuaranteedFailureJobId {
            return false
        }
        // If we're going to check with the server, capture the newest job ID
        // BEFORE issuing the request. This ensures that jobs enqueued after we
        // start this fetch will issue their own fetch.
        let newestJobId: Int64? = self.newestJobId()

        // If that fails, fall back to a fetch via the service.
        if try await tryToUpdateUsingService(jobInfo: jobInfo) {
            return true
        }

        // If we can't fetch via the service, store that result for reuse in future
        // invocations of this method.
        newestGuaranteedFailureJobId = newestJobId
        return false
    }

    /// Try to apply a single embedded (peer-to-peer) update.
    ///
    /// This method should:
    ///
    /// * Return true if message processing should proceed. This means that the
    /// group state has been updated to (at least) the message's revision.
    ///
    /// * Return false if the group could not be updated to the target revision
    /// and we should fail over to fetching group changes and/or latest group
    /// state from the service.
    private func updateUsingEmbeddedGroupUpdate(
        jobInfo: IncomingGroupsV2MessageJobInfo,
    ) async throws(RetryableError) -> Bool {
        let groupId = jobInfo.groupContextInfo.groupId
        let secretParams = jobInfo.groupContextInfo.groupSecretParams

        // TODO: Move this to the other method to avoid duplicate fetches.
        let groupThread = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return TSGroupThread.fetch(forGroupId: groupId, tx: tx)
        }
        guard
            let groupThread,
            let oldGroupModel = groupThread.groupModel as? TSGroupModelV2,
            jobInfo.groupContext.revision == oldGroupModel.revision + 1
        else {
            // We might be learning of a group for the first time, or we might be
            // getting re-added to a group we were previously a member of, or we might
            // have been offline for a while and lost messages in our queue. In all of
            // these cases, we need to fall back to the service.
            return false
        }

        guard let changeProtoData = jobInfo.groupContext.groupChange else {
            // No embedded group change.
            return false
        }

        let changeActionsProto: GroupsProtoGroupChangeActions
        do {
            let changeProto = try GroupsProtoGroupChange(serializedData: changeProtoData)
            guard changeProto.changeEpoch <= GroupManager.changeProtoEpoch else {
                throw OWSGenericError("Not-yet-supported embedded change proto epoch: \(changeProto.changeEpoch).")
            }

            // We need to verify the signatures because these protos came from another
            // client, not the service.
            changeActionsProto = try GroupsV2Protos.parseGroupChangeProto(changeProto, verificationOperation: .verifySignature(groupId: groupId.serialize()))
        } catch {
            Logger.warn("Couldn't verify change actions: \(error)")
            return false
        }

        guard changeActionsProto.revision == jobInfo.groupContext.revision else {
            owsFailDebug("Embedded change proto revision doesn't match context revision.")
            return false
        }

        do {
            let spamReportingMetadata: GroupUpdateSpamReportingMetadata = {
                guard let serverGuid = ValidatedIncomingEnvelope.parseServerGuid(fromEnvelope: jobInfo.envelope) else {
                    return .unreportable
                }
                return .reportable(serverGuid: serverGuid.uuidString.lowercased())
            }()
            try await SSKEnvironment.shared.groupsV2Ref.updateGroupWithChangeActions(
                spamReportingMetadata: spamReportingMetadata,
                changeActionsProto: changeActionsProto,
                groupSecretParams: secretParams,
            )
        } catch {
            if let retryableError = RetryableError(error) {
                throw retryableError
            }
            if case GroupsV2Error.cantApplyChangesToPlaceholder = error {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")
            }
            return false
        }

        return true
    }

    private func tryToUpdateUsingService(jobInfo: IncomingGroupsV2MessageJobInfo) async throws(RetryableError) -> Bool {
        let spamReportingMetadata: GroupUpdateSpamReportingMetadata = {
            guard let serverGuid = ValidatedIncomingEnvelope.parseServerGuid(fromEnvelope: jobInfo.envelope) else {
                return .unreportable
            }
            return .reportable(serverGuid: serverGuid.uuidString.lowercased())
        }()
        do {
            try await SSKEnvironment.shared.groupV2UpdatesRef.refreshGroup(
                secretParams: jobInfo.groupContextInfo.groupSecretParams,
                spamReportingMetadata: spamReportingMetadata,
                source: .groupMessage(revision: jobInfo.groupContext.revision),
            )
            return true
        } catch {
            if let retryableError = RetryableError(error) {
                throw retryableError
            }
            if case GroupsV2Error.localUserNotInGroup = error {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }
            return false
        }
    }

    private struct RetryableError: Error {
        let rawValue: any Error

        init?(_ error: any Error) {
            guard Self.isRetryableError(error) else {
                return nil
            }
            self.rawValue = error
        }

        private static func isRetryableError(_ error: any Error) -> Bool {
            if error.isNetworkFailureOrTimeout {
                return true
            }
            if let statusCode = error.httpStatusCode {
                if statusCode == 401 || (500 <= statusCode && statusCode <= 599) {
                    return true
                }
            }
            switch error {
            case GroupsV2Error.timeout:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: -

public class GroupMessageProcessorManager {

    public static let didFlushGroupsV2MessageQueue = Notification.Name("didFlushGroupsV2MessageQueue")

    private let finder = GroupMessageProcessorJobStore()

    public init() {
        SwiftSingletons.register(self)
    }

    // MARK: -

    private struct State {
        var activeGroupIds = Set<Data>()
        var pendingGroupIds = Set<Data>()
    }

    private let state = AtomicValue(State(), lock: .init())

    /// Starts a processor for every groupId with pending work.
    public func startAllProcessors() async {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            return
        }

        // Obtain the list of groups that currently need processing.
        let db = DependenciesBridge.shared.db
        let groupIds = db.read { tx -> Set<Data> in
            return Set(finder.allEnqueuedGroupIds(tx: tx))
        }

        if !groupIds.isEmpty {
            Logger.info("(Re-)starting \(groupIds.count) group message processor(s) with pending messages.")
        }

        for groupId in groupIds {
            startProcessorIfNeeded(groupId: groupId)
        }
    }

    private func startProcessorIfNeeded(groupId: Data) {
        let canStart = state.update {
            // Indicate that there's more work (in case it's already running).
            $0.pendingGroupIds.insert(groupId)
            // Start it now if it's not currently running.
            return $0.activeGroupIds.insert(groupId).inserted
        }
        guard canStart else {
            // It's already running, so there's nothing to do.
            return
        }
        // This Task must not be canceled.
        Task {
            var mightHaveMoreWork = true
            while mightHaveMoreWork {
                var didCallWillFetchNextJobs = false
                await SpecificGroupMessageProcessor(groupId: groupId).processBatches(willFetchNextJobs: {
                    state.update(block: { $0.pendingGroupIds.remove(groupId) })
                    didCallWillFetchNextJobs = true
                })
                owsPrecondition(didCallWillFetchNextJobs)
                // There is a race condition where `processBatches()` sees that there's no
                // work left to do and stops executing; however, before this code can
                // remove `groupId` from `activeGroupIds`, another component enqueues new
                // work, calls `startProcessorIfNeeded()`, and returns early because a
                // processor is already running. In this case, we'd "never" process the job
                // (the current processor is stopping; the new one doesn't start). By
                // checking `pendingGroupIds` before clearing `activeGroupIds`, we ensure
                // that (a) this processor will perform the work; or (b) this processor
                // will stop and the next invocation of this method will start a new one.
                //
                // See also: GroupsV2ProfileKeyUpdater's isUpdating/needsUpdate flags.
                mightHaveMoreWork = state.update(block: {
                    if $0.pendingGroupIds.contains(groupId) {
                        return true
                    }
                    $0.activeGroupIds.remove(groupId)
                    if $0.activeGroupIds.isEmpty {
                        NotificationCenter.default.postOnMainThread(name: GroupMessageProcessorManager.didFlushGroupsV2MessageQueue, object: nil)
                    }
                    return false
                })
            }
        }
    }

    // MARK: -

    func enqueue(
        envelope: DecryptedIncomingEnvelope,
        envelopeData: Data,
        serverDeliveryTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        guard !envelopeData.isEmpty else {
            owsFailDebug("Empty envelope.")
            return
        }

        guard let groupId = Self.groupId(from: envelope.content) else {
            owsFailDebug("Missing or invalid group id")
            return
        }

        // We need to persist the decrypted envelope data in this transaction to
        // prevent data loss.
        failIfThrows {
            _ = try GroupMessageProcessorJob.insertRecord(
                envelopeData: envelopeData,
                plaintextData: envelope.plaintextData,
                groupId: groupId,
                wasReceivedByUD: envelope.wasReceivedByUD,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                tx: tx,
            )
        }

        // The new envelope won't be visible to the processor until this
        // transaction commits, so start it in the transaction completion.
        tx.addSyncCompletion {
            self.startProcessorIfNeeded(groupId: groupId)
        }
    }

    private static func groupId(from contentProto: SSKProtoContent?) -> Data? {
        guard let contentProto, let groupContext = groupContextV2(from: contentProto) else {
            owsFailDebug("Invalid content.")
            return nil
        }
        do {
            let groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupContext.masterKey ?? Data())
            return groupContextInfo.groupId.serialize()
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return nil
        }
    }

    public class func canContextBeProcessedImmediately(
        groupContext: SSKProtoGroupContextV2,
        tx: DBReadTransaction,
    ) -> Bool {
        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupContext.masterKey ?? Data())
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return false
        }

        // We can only process GV2 messages immediately if:
        // 1. We don't have any other messages queued for this thread
        // 2. The message can be processed without updates

        let existsJob: Bool = GroupMessageProcessorJobStore().existsJob(
            forGroupId: groupContextInfo.groupId.serialize(),
            tx: tx,
        )
        if existsJob {
            Logger.info("Cannot immediately process GV2 message because there are messages queued.")
            return false
        }

        return canContextBeProcessedWithoutUpdate(
            groupContext: groupContext,
            groupContextInfo: groupContextInfo,
            tx: tx,
        )
    }

    fileprivate class func canContextBeProcessedWithoutUpdate(
        groupContext: SSKProtoGroupContextV2,
        groupContextInfo: GroupV2ContextInfo,
        tx: DBReadTransaction,
    ) -> Bool {
        guard let groupThread = TSGroupThread.fetch(forGroupId: groupContextInfo.groupId, tx: tx) else {
            return false
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return true
        }
        let messageRevision = groupContext.revision
        let modelRevision = groupModel.revision
        if messageRevision <= modelRevision {
            return true
        }
        // The incoming message indicates that there is a new group revision. We'll
        // update our group model using either the change proto embedded in the
        // group context or by fetching latest state from the service.
        return false
    }

    fileprivate static func groupContextV2(fromPlaintextData plaintextData: Data) -> SSKProtoGroupContextV2? {
        guard !plaintextData.isEmpty else {
            return nil
        }

        let contentProto: SSKProtoContent
        do {
            contentProto = try SSKProtoContent(serializedData: plaintextData)
        } catch {
            owsFailDebug("could not parse proto: \(error)")
            return nil
        }

        return groupContextV2(from: contentProto)
    }

    public class func groupContextV2(from contentProto: SSKProtoContent) -> SSKProtoGroupContextV2? {
        if let groupV2 = contentProto.dataMessage?.groupV2 {
            return groupV2
        }
        if let groupV2 = contentProto.editMessage?.dataMessage?.groupV2 {
            return groupV2
        }
        if let groupV2 = contentProto.syncMessage?.sent?.message?.groupV2 {
            return groupV2
        }
        if let groupV2 = contentProto.syncMessage?.sent?.editMessage?.dataMessage?.groupV2 {
            return groupV2
        }
        return nil
    }

    public func isProcessing() -> Bool {
        return self.state.update(block: { !$0.activeGroupIds.isEmpty })
    }

    public enum DiscardMode {
        /// Do not process this envelope.
        case discard
        /// Process this envelope.
        case doNotDiscard
        /// Process this envelope, but discard any "renderable" content,
        /// e.g. calls or messages in the chat history.
        case discardVisibleMessages
    }

    /// Returns whether a group message from the given user should be discarded.
    ///
    /// If `shouldCheckGroupModel` is false, only checks whether the sender or
    /// group is blocked.
    public static func discardMode(
        forMessageFrom sourceAci: Aci,
        groupId: GroupIdentifier,
        shouldCheckGroupModel: Bool = true,
        tx: DBReadTransaction,
    ) -> DiscardMode {
        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let isBlocked: Bool = (
            blockingManager.isAddressBlocked(SignalServiceAddress(sourceAci), transaction: tx)
                || blockingManager.isGroupIdBlocked(groupId, transaction: tx),
        )
        if isBlocked {
            Logger.info("Discarding blocked envelope.")
            return .discard
        }

        // We need to pre-process all incoming envelopes; they might change our
        // group state.
        //
        // But we should only pass envelopes to the MessageManager for processing
        // if they correspond to v2 groups of which we are a non-pending member.
        if shouldCheckGroupModel {
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                owsFailDebug("Missing localAddress.")
                return .discard
            }
            guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx) else {
                // The user might have just deleted the thread
                // but this race should be extremely rare.
                // Usually this should indicate a bug.
                owsFailDebug("Missing thread.")
                return .discard
            }
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid group model.")
                return .discard
            }
            guard groupModel.groupMembership.isFullMember(localAddress) else {
                // * Local user might have just left the group.
                // * Local user may have just learned that we were removed from the group.
                // * Local user might be a pending member with an invite.
                Logger.warn("Discarding envelope; local user is not an active group member.")
                return .discard
            }
            guard groupModel.groupMembership.isFullMember(SignalServiceAddress(sourceAci)) else {
                // * The sender might have just left the group.
                Logger.warn("Discarding envelope; sender is not an active group member.")
                return .discard
            }
            if groupModel.isAnnouncementsOnly {
                guard groupModel.groupMembership.isFullMemberAndAdministrator(SignalServiceAddress(sourceAci)) else {
                    // * Only administrators can send "renderable" messages to a "announcement-only" group.
                    Logger.warn("Discarding renderable content in envelope; sender is not an active group member.")
                    return .discardVisibleMessages
                }
            }
        }

        return .doNotDiscard
    }
}
