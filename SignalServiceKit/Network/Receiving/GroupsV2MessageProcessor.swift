//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

private struct IncomingGroupsV2MessageJobInfo {
    let job: IncomingGroupsV2MessageJob
    var envelope: SSKProtoEnvelope?
    var groupContext: SSKProtoGroupContextV2?
    var groupContextInfo: GroupV2ContextInfo?
}

// MARK: -

class IncomingGroupsV2MessageQueue: MessageProcessingPipelineStage {

    private let appReadiness: AppReadiness
    private let finder = GRDBGroupsV2MessageJobFinder()

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        SwiftSingletons.register(self)

        observeNotifications()

        // Start processing.
        drainQueueWhenReady()
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(chatConnectionStateDidChange),
            name: OWSChatConnection.chatConnectionStateDidChange,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            SSKEnvironment.shared.messagePipelineSupervisorRef.register(pipelineStage: self)
        }
    }

    // MARK: - Notifications

    @objc
    func applicationWillEnterForeground() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
    }

    @objc
    func applicationDidEnterBackground() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
    }

    @objc
    func chatConnectionStateDidChange() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
    }

    @objc
    func reachabilityChanged() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
    }

    func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
        DispatchQueue.main.async {
            self.drainQueueWhenReady()
        }
    }

    // MARK: -

    fileprivate func enqueue(
        envelopeData: Data,
        plaintextData: Data,
        groupId: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        // We need to persist the decrypted envelope data ASAP to prevent data loss.
        finder.addJob(
            envelopeData: envelopeData,
            plaintextData: plaintextData,
            groupId: groupId,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            transaction: tx.unwrapGrdbWrite
        )
    }

    fileprivate func drainQueueWhenReady() {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            return
        }
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            DispatchQueue.global().async {
                self.drainQueues()
            }
        }
    }

    private let unfairLock = UnfairLock()
    private var groupIdsBeingProcessed: Set<Data> = Set()

    fileprivate var isActivelyProcessing: Bool {
        return unfairLock.withLock {
            return groupIdsBeingProcessed.isEmpty.negated
        }
    }

    // At any given time, we need to ensure that there is exactly
    // one GroupsMessageProcessor for each group that needs to
    // process incoming messages.
    private func drainQueues() {
        owsAssertDebug(!Thread.isMainThread)

        guard appReadiness.isAppReady || CurrentAppContext().isRunningTests else {
            owsFailDebug("App is not ready.")
            return
        }

        let canProcess = (
            SSKEnvironment.shared.messagePipelineSupervisorRef.isMessageProcessingPermitted &&
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        )

        guard canProcess else {
            // Don't process queues.
            return
        }

        // Obtain the list of groups that currently need processing.
        let groupIdsWithJobs = Set(SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.finder.allEnqueuedGroupIds(transaction: transaction.unwrapGrdbRead)
        })

        guard !groupIdsWithJobs.isEmpty else {
            NotificationCenter.default.postNotificationNameAsync(GroupsV2MessageProcessor.didFlushGroupsV2MessageQueue, object: nil)
            return
        }

        let messageProcessors: [GroupsMessageProcessor] = unfairLock.withLock {
            let groupIdsToProcess = groupIdsWithJobs.subtracting(groupIdsBeingProcessed)
            groupIdsBeingProcessed.formUnion(groupIdsToProcess)

            return groupIdsToProcess.map { GroupsMessageProcessor(groupId: $0, appReadiness: appReadiness) }
        }

        for processor in messageProcessors {
            firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                processor.promise
            }.ensure(on: DispatchQueue.global()) {
                self.unfairLock.withLock {
                    _ = self.groupIdsBeingProcessed.remove(processor.groupId)
                }
                self.drainQueues()
            }.catch(on: DispatchQueue.global()) { error in
                owsFailDebug("Error: \(error)")
            }
        }
    }

    func hasPendingJobs(tx: SDSAnyReadTransaction) -> Bool {
        self.finder.jobCount(transaction: tx) > 0
    }

    func pendingJobCount(tx: SDSAnyReadTransaction) -> UInt {
        self.finder.jobCount(transaction: tx)
    }
}

// MARK: -

// The entity tries to process all pending jobs for a given group.
//
// * It retries with exponential backoff.
// * It retries immediately if reachability, etc. change.
//
// It's promise is fulfilled when all jobs are processed _or_
// we give up.
internal class GroupsMessageProcessor: MessageProcessingPipelineStage {

    private let appReadiness: AppReadiness

    fileprivate let groupId: Data
    private let finder = GRDBGroupsV2MessageJobFinder()

    fileprivate let promise: Promise<Void>
    private let future: Future<Void>

    internal init(groupId: Data, appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        self.groupId = groupId

        let (promise, future) = Promise<Void>.pending()
        self.promise = promise
        self.future = future

        observeNotifications()

        tryToProcess()
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(chatConnectionStateDidChange),
            name: OWSChatConnection.chatConnectionStateDidChange,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            SSKEnvironment.shared.messagePipelineSupervisorRef.register(pipelineStage: self)
        }
    }

    // MARK: - Notifications

    @objc
    func applicationWillEnterForeground() {
        AssertIsOnMainThread()

        tryToProcess()
    }

    @objc
    func applicationDidEnterBackground() {
        AssertIsOnMainThread()

        tryToProcess()
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        tryToProcess()
    }

    @objc
    func chatConnectionStateDidChange() {
        AssertIsOnMainThread()

        tryToProcess()
    }

    @objc
    func reachabilityChanged() {
        AssertIsOnMainThread()

        tryToProcess()
    }

    // MARK: -

    private let isDrainingQueue = AtomicBool(false, lock: .sharedGlobal)

    private func tryToProcess(retryDelayAfterFailure: TimeInterval = 1.0) {
        guard isDrainingQueue.tryToSetFlag() else {
            // Batch already in flight.
            return
        }
        processWorkStep(retryDelayAfterFailure: retryDelayAfterFailure)
    }

    private typealias BatchCompletionBlock = ([IncomingGroupsV2MessageJob], Bool, SDSAnyWriteTransaction) -> Void

    private func processWorkStep(retryDelayAfterFailure: TimeInterval = 1.0) {
        owsAssertDebug(isDrainingQueue.get())

        let canProcess = (
            SSKEnvironment.shared.messagePipelineSupervisorRef.isMessageProcessingPermitted &&
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        )

        guard canProcess else {
            Logger.warn("Cannot process.")
            future.resolve()
            return
        }

        // We want a value that is just high enough to yield perf benefits.
        let kIncomingMessageBatchSize: UInt = 16
        // If the app is in the background, use batch size of 1.
        // This reduces the cost of being interrupted and rolled back if
        // app is suspended.
        let batchSize: UInt = CurrentAppContext().isInBackground() ? 1 : kIncomingMessageBatchSize

        let batchJobs = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.finder.nextJobs(forGroupId: self.groupId, batchSize: batchSize, transaction: transaction.unwrapGrdbRead)
        }
        guard !batchJobs.isEmpty else {
            future.resolve()
            return
        }

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)")
        let completion: BatchCompletionBlock = { (processedJobs, shouldWaitBeforeRetrying, transaction) in
            // NOTE: This transaction is the same transaction as the transaction
            //       passed to processJobs() in the "sync" case but is a different
            //       transaction in the "async" case.

            if shouldWaitBeforeRetrying {
                Logger.warn("shouldWaitBeforeRetrying")
            }

            let processedUniqueIds = processedJobs.map { $0.uniqueId }
            self.finder.removeJobs(withUniqueIds: processedUniqueIds, transaction: transaction.unwrapGrdbWrite)

            transaction.addAsyncCompletionOffMain {
                assert(backgroundTask != nil)
                backgroundTask = nil

                if shouldWaitBeforeRetrying {
                    // After successfully processing a batch drainQueueWorkStep()
                    // calls itself to process the next batch, if any.
                    // The isDrainingQueue flag is cleared when all batches have
                    // been processed.
                    //
                    // After failures, we clear isDrainingQueue immediately and
                    // call drainQueue(), not drainQueueWorkStep() after a delay.
                    // That allows us to kick off another batch immediately if
                    // reachability changes, etc.
                    if !self.isDrainingQueue.tryToClearFlag() {
                        self.future.reject(OWSAssertionError("Couldn't clear flag."))
                        return
                    }
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelayAfterFailure) {
                        self.tryToProcess(retryDelayAfterFailure: retryDelayAfterFailure * 2)
                    }
                } else {
                    // Wait always a bit in hopes of increasing the size of the next batch.
                    // This delay won't affect the first message to arrive when this queue is idle,
                    // so by definition we're receiving more than one message and can benefit from
                    // batching.
                    let batchSpacingSeconds: TimeInterval = 0.5
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + batchSpacingSeconds) {
                        self.processWorkStep()
                    }
                }
            }
        }

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            self.processJobs(jobs: batchJobs, tx: tx, completion: completion)
        }
    }

    private static func jobInfo(
        forJob job: IncomingGroupsV2MessageJob,
        tx: SDSAnyReadTransaction
    ) -> IncomingGroupsV2MessageJobInfo {
        var jobInfo = IncomingGroupsV2MessageJobInfo(job: job)
        guard let envelope = job.envelope else {
            owsFailDebug("Missing envelope.")
            return jobInfo
        }
        jobInfo.envelope = envelope
        guard let plaintextData = job.plaintextData,
              let groupContext = GroupsV2MessageProcessor.groupContextV2(fromPlaintextData: plaintextData) else {
            owsFailDebug("Missing group context.")
            return jobInfo
        }
        jobInfo.groupContext = groupContext
        do {
            jobInfo.groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupContext.masterKey ?? Data())
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return jobInfo
        }

        return jobInfo
    }

    internal static func discardMode(
        forMessageFrom sourceAci: Aci,
        groupContext: SSKProtoGroupContextV2,
        tx: SDSAnyReadTransaction
    ) -> GroupsV2MessageProcessor.DiscardMode {
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

        return GroupsV2MessageProcessor.discardMode(
            forMessageFrom: sourceAci,
            groupId: groupContextInfo.groupId,
            tx: tx
        )
    }

    private static func discardMode(
        forJobInfo jobInfo: IncomingGroupsV2MessageJobInfo,
        hasGroupBeenUpdated: Bool,
        tx: SDSAnyReadTransaction
    ) -> GroupsV2MessageProcessor.DiscardMode {
        guard let envelope = jobInfo.envelope else {
            owsFailDebug("Missing envelope.")
            return .discard
        }
        guard let groupContextInfo = jobInfo.groupContextInfo else {
            owsFailDebug("Missing groupContextInfo.")
            return .discard
        }
        guard let sourceAci = Aci.parseFrom(aciString: envelope.sourceServiceID) else {
            owsFailDebug("Invalid source address.")
            return .discard
        }
        return GroupsV2MessageProcessor.discardMode(
            forMessageFrom: sourceAci,
            groupId: groupContextInfo.groupId,
            shouldCheckGroupModel: hasGroupBeenUpdated,
            tx: tx
        )
    }

    // Like non-v2 group messages, we want to do batch processing
    // wherever possible for perf reasons (to reduce view updates).
    // We should be able to mostly do that. However, in some cases
    // we need to update the group  before we can process the
    // message. Such messages should be processed in a batch
    // of their own.
    //
    // Therefore, when trying to process we try to process either:
    //
    // * The first N messages that can be processed "without update".
    // * The first message, which has to be processed "with update".
    //
    // Which type of batch we try to process is determined by the
    // message at the head of the queue.
    private func canJobBeProcessedWithoutUpdate(
        jobInfo: IncomingGroupsV2MessageJobInfo,
        tx: SDSAnyReadTransaction
    ) -> Bool {
        if .discard == Self.discardMode(forJobInfo: jobInfo, hasGroupBeenUpdated: false, tx: tx) {
            return true
        }
        guard let groupContext = jobInfo.groupContext else {
            owsFailDebug("Missing groupContext.")
            return true
        }
        guard let groupContextInfo = jobInfo.groupContextInfo else {
            owsFailDebug("Missing groupContextInfo.")
            return true
        }
        return GroupsV2MessageProcessor.canContextBeProcessedWithoutUpdate(
            groupContext: groupContext,
            groupContextInfo: groupContextInfo,
            tx: tx
        )
    }

    // NOTE: This method might do its work synchronously (in the "no update" case)
    //       or asynchronously (in the "update" case).  It may only process
    //       a subset of the jobs.
    private func processJobs(
        jobs: [IncomingGroupsV2MessageJob],
        tx: SDSAnyWriteTransaction,
        completion: @escaping BatchCompletionBlock
    ) {

        // 1. Gather info for each job.
        // 2. Decide whether we'll process 1 "update" job or N "no update" jobs.
        //
        // "Update" jobs may require interaction with the service, namely
        // fetching group changes or latest group state.
        var isUpdateBatch = false
        var jobInfos = [IncomingGroupsV2MessageJobInfo]()
        for job in jobs {
            let jobInfo = Self.jobInfo(forJob: job, tx: tx)
            let canJobBeProcessedWithoutUpdate = self.canJobBeProcessedWithoutUpdate(jobInfo: jobInfo, tx: tx)
            if !canJobBeProcessedWithoutUpdate {
                if jobInfos.count > 0 {
                    // Can't add "update" job to "no update" batch, abort and process jobs
                    // already added to batch.
                    break
                }
                // Update batches should only contain a single job.
                isUpdateBatch = true
                jobInfos.append(jobInfo)
                break
            }
            jobInfos.append(jobInfo)
        }

        if isUpdateBatch {
            assert(jobInfos.count == 1)
            guard let jobInfo = jobInfos.first else {
                owsFailDebug("Missing job")
                completion([], false, tx)
                return
            }
            Task {
                await updateGroupAndProcessJob(jobInfo: jobInfo, completion: completion)
            }
        } else {
            let processedJobs = performLocalProcessingSync(jobInfos: jobInfos, tx: tx)
            completion(processedJobs, false, tx)
        }
    }

    private func performLocalProcessingSync(
        jobInfos: [IncomingGroupsV2MessageJobInfo],
        tx: SDSAnyWriteTransaction
    ) -> [IncomingGroupsV2MessageJob] {
        guard jobInfos.count > 0 else {
            owsFailDebug("Missing jobInfos.")
            return []
        }

        var processedJobs = [IncomingGroupsV2MessageJob]()
        for jobInfo in jobInfos {
            let job = jobInfo.job

            let discardMode = Self.discardMode(forJobInfo: jobInfo, hasGroupBeenUpdated: true, tx: tx)
            if discardMode == .discard {
                // Do nothing.
            } else {
                // The forced unwraps are checked in `discardMode`, so they can't fail.
                // TODO: Refactor so that the compiler enforces the above statement.
                SSKEnvironment.shared.messageReceiverRef.processEnvelope(
                    jobInfo.envelope!,
                    plaintextData: job.plaintextData!,
                    wasReceivedByUD: job.wasReceivedByUD,
                    serverDeliveryTimestamp: job.serverDeliveryTimestamp,
                    shouldDiscardVisibleMessages: discardMode == .discardVisibleMessages,
                    localIdentifiers: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)!,
                    tx: tx
                )
            }
            processedJobs.append(job)

            if CurrentAppContext().isInBackground() {
                // If the app is in the background, stop processing this batch.
                //
                // Since this check is done after processing jobs, we'll continue
                // to process jobs in batches of 1.  This reduces the cost of
                // being interrupted and rolled back if app is suspended.
                break
            }
        }
        return processedJobs
    }

    private enum UpdateOutcome {
        case successShouldProcess
        case failureShouldDiscard
        case failureShouldRetry
        case failureShouldFailoverToService
    }

    private func updateGroupAndProcessJob(
        jobInfo: IncomingGroupsV2MessageJobInfo,
        completion: @escaping BatchCompletionBlock
    ) async {
        do {
            let updateOutcome = await updateGroup(jobInfo: jobInfo)
            switch updateOutcome {
            case .successShouldProcess:
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    let processedJobs = self.performLocalProcessingSync(jobInfos: [jobInfo], tx: tx)
                    completion(processedJobs, false, tx)
                }
            case .failureShouldDiscard:
                throw GroupsV2Error.shouldDiscard
            case .failureShouldRetry:
                throw GroupsV2Error.shouldRetry
            case .failureShouldFailoverToService:
                owsFailDebug("Invalid embeddedUpdateOutcome: .failureShouldFailoverToService.")
                throw GroupsV2Error.shouldDiscard
            }
        } catch {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                if self.isRetryableError(error) {
                    Logger.warn("Error: \(error)")
                    // Retry
                    // _Do not_ include the job in the processed jobs.
                    // _Do_ wait before retrying.
                    completion([], true, tx)
                } else {
                    // This should only occur if we no longer have access to group state,
                    // e.g. a) we were kicked out of the group. b) our invite was revoked.
                    // c) our request to join via group invite link was denied.
                    Logger.warn("Discarding unprocess-able message: \(error)")

                    // Do not retry
                    // _Do_ include the job in the processed jobs.
                    //      It will be discarded.
                    // _Do not_ wait before retrying.
                    completion([jobInfo.job], false, tx)
                }
            }
        }
    }

    private func updateGroup(jobInfo: IncomingGroupsV2MessageJobInfo) async -> UpdateOutcome {
        // First, we try to update the group locally using changes embedded in
        // the group context (if any).
        let embeddedUpdateOutcome = await updateUsingEmbeddedGroupUpdate(jobInfo: jobInfo)
        if embeddedUpdateOutcome == .failureShouldFailoverToService {
            return await tryToUpdateUsingService(jobInfo: jobInfo)
        } else {
            return embeddedUpdateOutcome
        }
    }

    // We only try to apply one embedded update per batch.
    //
    // If applying the embedded update fails, we fail
    // over to fetching latest state from service.
    //
    // This method should:
    //
    // * Return .successShouldProcess if message processing should proceed. Either:
    //   * ...the group didn't need to be updated (some other component beat us to it).
    //   * ...the group was successfully updated to the target revision.
    // * Return .failureShouldFailoverToService if the group could not be updated
    //   to the target revision and we should fail over to fetching group changes
    //   and/or latest group state from the service.
    // * Return .failureShouldDiscard if this message should be discarded.
    //
    // This method should never return .failureShouldRetry.
    private func updateUsingEmbeddedGroupUpdate(
        jobInfo: IncomingGroupsV2MessageJobInfo
    ) async -> UpdateOutcome {
        guard
            let groupContextInfo = jobInfo.groupContextInfo,
            let groupContext = jobInfo.groupContext
        else {
            owsFailDebug("Missing jobInfo properties.")
            return .failureShouldDiscard
        }
        let groupId = groupContextInfo.groupId
        guard GroupManager.isValidGroupId(groupId, groupsVersion: .V2) else {
            owsFailDebug("Invalid groupId.")
            return .failureShouldDiscard
        }
        let thread = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return TSGroupThread.fetch(groupId: groupId, transaction: tx)
        }
        guard let groupThread = thread else {
            // We might be learning of a group for the first time
            // in which case we should fetch current group state from the
            // service.
            return .failureShouldFailoverToService
        }
        guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return .failureShouldDiscard
        }
        guard groupContext.hasRevision else {
            owsFailDebug("Missing revision.")
            return .failureShouldDiscard
        }
        let contextRevision = groupContext.revision
        guard contextRevision > oldGroupModel.revision else {
            // Group is already updated.
            // No need to apply embedded change from the group context; it is obsolete.
            // This can happen due to races.
            return .successShouldProcess
        }
        guard contextRevision == oldGroupModel.revision + 1 else {
            // We can only apply embedded changes if we're behind exactly
            // one revision.
            return .failureShouldFailoverToService
        }
        guard let changeProtoData = groupContext.groupChange else {
            // No embedded group change.
            return .failureShouldFailoverToService
        }

        do {
            let changeProto = try GroupsProtoGroupChange(serializedData: changeProtoData)
            guard changeProto.changeEpoch <= GroupManager.changeProtoEpoch else {
                throw OWSAssertionError("Invalid embedded change proto epoch: \(changeProto.changeEpoch).")
            }

            // We need to verify the signatures because these protos came from
            // another client, not the service.
            let changeActionsProto = try GroupsV2Protos.parseGroupChangeProto(changeProto, verificationOperation: .verifySignature(groupId: groupId))

            guard changeActionsProto.revision == contextRevision else {
                throw OWSAssertionError("Embedded change proto revision doesn't match context revision.")
            }

            let spamReportingMetadata: GroupUpdateSpamReportingMetadata = {
                guard let serverGuid = jobInfo.envelope?.serverGuid else { return .unreportable }
                return .reportable(serverGuid: serverGuid)
            }()
            let updatedGroupThread = try await SSKEnvironment.shared.groupsV2Ref.updateGroupWithChangeActions(
                groupId: oldGroupModel.groupId,
                spamReportingMetadata: spamReportingMetadata,
                changeActionsProto: changeActionsProto,
                groupSecretParams: try oldGroupModel.secretParams()
            )

            guard let updatedGroupModel = updatedGroupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid group model.")
                return .failureShouldFailoverToService
            }
            guard updatedGroupModel.revision >= contextRevision else {
                owsFailDebug("Invalid revision.")
                return .failureShouldFailoverToService
            }
            guard updatedGroupModel.revision == contextRevision else {
                // We expect the embedded changes to update us to the target
                // revision.  If we update past that, assert but proceed in production.
                owsFailDebug("Unexpected revision.")
                return .successShouldProcess
            }
        } catch {
            if self.isRetryableError(error) {
                Logger.warn("Error: \(error)")
                return .failureShouldRetry
            } else {
                if case GroupsV2Error.cantApplyChangesToPlaceholder = error {
                    Logger.warn("Error: \(error)")
                } else {
                    owsFailDebug("Error: \(error)")
                }
                return .failureShouldFailoverToService
            }
        }

        Logger.info("Successfully applied embedded change proto from group context.")
        return .successShouldProcess
    }

    private func tryToUpdateUsingService(jobInfo: IncomingGroupsV2MessageJobInfo) async -> UpdateOutcome {
        guard
            let groupContextInfo = jobInfo.groupContextInfo,
            let groupContext = jobInfo.groupContext
        else {
            owsFailDebug("Missing jobInfo properties.")
            return .failureShouldDiscard
        }

        // See GroupV2UpdatesImpl.
        // This will try to update the group using incremental "changes" but
        // failover to using a "snapshot".
        let spamReportingMetadata: GroupUpdateSpamReportingMetadata = {
            guard let serverGuid = jobInfo.envelope?.serverGuid else { return .unreportable }
            return .reportable(serverGuid: serverGuid)
        }()
        let groupUpdateMode = GroupUpdateMode.upToSpecificRevisionImmediately(upToRevision: groupContext.revision)
        do {
            try await SSKEnvironment.shared.groupV2UpdatesRef.tryToRefreshV2GroupThread(
                groupId: groupContextInfo.groupId,
                spamReportingMetadata: spamReportingMetadata,
                groupSecretParams: groupContextInfo.groupSecretParams,
                groupUpdateMode: groupUpdateMode
            )
            return .successShouldProcess
        } catch {
            if self.isRetryableError(error) {
                Logger.warn("error: \(type(of: error)) \(error)")
                return .failureShouldRetry
            }

            if case GroupsV2Error.localUserNotInGroup = error {
                // This should only occur if we no longer have access to group state,
                // e.g. a) we were kicked out of the group. b) our invite was revoked.
                // c) our request to join via group invite link was denied.
                Logger.warn("Error: \(type(of: error)) \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }

            return .failureShouldDiscard
        }
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if error.isNetworkFailureOrTimeout {
            return true
        }
        if let statusCode = error.httpStatusCode {
            if statusCode == 401 ||
               (500 <= statusCode && statusCode <= 599) {
                return true
            }
        }
        switch error {
        case GroupsV2Error.timeout, GroupsV2Error.shouldRetry:
            return true
        default:
            return false
        }
    }
}

// MARK: -

public class GroupsV2MessageProcessor: NSObject {

    public static let didFlushGroupsV2MessageQueue = Notification.Name("didFlushGroupsV2MessageQueue")

    private let processingQueue: IncomingGroupsV2MessageQueue

    public init(appReadiness: AppReadiness) {
        self.processingQueue = IncomingGroupsV2MessageQueue(appReadiness: appReadiness)
        super.init()
        SwiftSingletons.register(self)
        processingQueue.drainQueueWhenReady()
    }

    // MARK: -

    public func enqueue(
        envelopeData: Data,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        guard !envelopeData.isEmpty else {
            owsFailDebug("Empty envelope.")
            return
        }

        guard let groupId = groupId(fromPlaintextData: plaintextData) else {
            owsFailDebug("Missing or invalid group id")
            return
        }

        // We need to persist the decrypted envelope data ASAP to prevent data loss.
        processingQueue.enqueue(
            envelopeData: envelopeData,
            plaintextData: plaintextData,
            groupId: groupId,
            wasReceivedByUD: wasReceivedByUD,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            tx: tx
        )

        if DebugFlags.internalLogging {
            let jobCount = processingQueue.pendingJobCount(tx: tx)
            Logger.info("jobCount: \(jobCount)")
        }

        // The new envelope won't be visible to the finder until this transaction commits,
        // so drainQueue in the transaction completion.
        tx.addAsyncCompletionOffMain {
            self.processingQueue.drainQueueWhenReady()
        }
    }

    private func groupId(fromPlaintextData plaintextData: Data) -> Data? {
        guard let groupContext = GroupsV2MessageProcessor.groupContextV2(fromPlaintextData: plaintextData) else {
            owsFailDebug("Invalid content.")
            return nil
        }
        do {
            let groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupContext.masterKey ?? Data())
            return groupContextInfo.groupId
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return nil
        }
    }

    public class func isGroupsV2Message(plaintextData: Data) -> Bool {
        return groupContextV2(fromPlaintextData: plaintextData) != nil
    }

    public class func canContextBeProcessedImmediately(
        groupContext: SSKProtoGroupContextV2,
        tx: SDSAnyReadTransaction
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

        guard !GRDBGroupsV2MessageJobFinder().existsJob(forGroupId: groupContextInfo.groupId, transaction: tx.unwrapGrdbRead) else {
            Logger.warn("Cannot immediately process GV2 message because there are messages queued")
            return false
        }

        return canContextBeProcessedWithoutUpdate(
            groupContext: groupContext,
            groupContextInfo: groupContextInfo,
            tx: tx
        )
    }

    fileprivate class func canContextBeProcessedWithoutUpdate(
        groupContext: SSKProtoGroupContextV2,
        groupContextInfo: GroupV2ContextInfo,
        tx: SDSAnyReadTransaction
    ) -> Bool {
        guard let groupThread = TSGroupThread.fetch(groupId: groupContextInfo.groupId, transaction: tx) else {
            return false
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            Logger.warn("Invalid group model; possibly needs to be migrated.")
            return false
        }
        let messageRevision = groupContext.revision
        let modelRevision = groupModel.revision
        if messageRevision <= modelRevision {
            return true
        }
        // The incoming message indicates that there is a new group revision.
        // We'll update our group model in a standalone batch using either
        // the change proto embedded in the group context or by fetching
        // latest state from the service.
        return false
    }

    public class func groupContextV2(fromPlaintextData plaintextData: Data) -> SSKProtoGroupContextV2? {
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
        if let groupV2 = contentProto.syncMessage?.sent?.message?.groupV2 {
            return groupV2
        }
        return nil
    }

    public func isActivelyProcessing() -> Bool {
        return processingQueue.isActivelyProcessing
    }

    public func hasPendingJobs(tx: SDSAnyReadTransaction) -> Bool {
        processingQueue.hasPendingJobs(tx: tx)
    }

    public func pendingJobCount(tx: SDSAnyReadTransaction) -> UInt {
        processingQueue.pendingJobCount(tx: tx)
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
    /// If `shouldCheckGroupModel` is false, only checks whether the sender or group is blocked.
    public static func discardMode(
        forMessageFrom sourceAci: Aci,
        groupId: Data,
        shouldCheckGroupModel: Bool = true,
        tx: SDSAnyReadTransaction
    ) -> DiscardMode {
        // We want to discard asap to avoid problems with batching.

        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let isBlocked: Bool = (
            blockingManager.isAddressBlocked(SignalServiceAddress(sourceAci), transaction: tx)
            || blockingManager.isGroupIdBlocked(groupId, transaction: tx)
        )
        if isBlocked {
            Logger.info("Discarding blocked envelope.")
            return .discard
        }

        // We need to pre-process all incoming envelopes; they might change
        // our group state.
        //
        // But we should only pass envelopes to the MessageManager for
        // processing if they correspond to v2 groups of which we are a
        // non-pending member.
        if shouldCheckGroupModel {
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
                owsFailDebug("Missing localAddress.")
                return .discard
            }
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: tx) else {
                // The user might have just deleted the thread
                // but this race should be extremely rare.
                // Usually this should indicate a bug.
                owsFailDebug("Missing thread.")
                return .discard
            }
            guard groupThread.groupModel.groupMembership.isFullMember(localAddress) else {
                // * Local user might have just left the group.
                // * Local user may have just learned that we were removed from the group.
                // * Local user might be a pending member with an invite.
                Logger.warn("Discarding envelope; local user is not an active group member.")
                return .discard
            }
            guard groupThread.groupModel.groupMembership.isFullMember(SignalServiceAddress(sourceAci)) else {
                // * The sender might have just left the group.
                Logger.warn("Discarding envelope; sender is not an active group member.")
                return .discard
            }
            if let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                if groupModel.isAnnouncementsOnly {
                    guard groupThread.groupModel.groupMembership.isFullMemberAndAdministrator(SignalServiceAddress(sourceAci)) else {
                        // * Only administrators can send "renderable" messages to a "announcement-only" group.
                        Logger.warn("Discarding renderable content in envelope; sender is not an active group member.")
                        return .discardVisibleMessages
                    }
                }
            } else {
                owsFailDebug("Invalid group model.")
            }
        }

        return .doNotDiscard
    }
}
