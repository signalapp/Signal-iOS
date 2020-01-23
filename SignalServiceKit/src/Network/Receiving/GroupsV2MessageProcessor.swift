//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private struct IncomingGroupsV2MessageJobInfo {
    let job: IncomingGroupsV2MessageJob
    var envelope: SSKProtoEnvelope?
    var groupContext: SSKProtoGroupContextV2?
    var groupContextInfo: GroupV2ContextInfo?
}

// MARK: -

class IncomingGroupsV2MessageQueue: NSObject {

    // MARK: - Dependencies

    private var messageManager: OWSMessageManager {
        return SSKEnvironment.shared.messageManager
    }

    private var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    private var blockingManager: OWSBlockingManager {
        return SSKEnvironment.shared.blockingManager
    }

    private var notificationsManager: NotificationsProtocol {
        return SSKEnvironment.shared.notificationsManager
    }

    // MARK: -

    private let finder = GRDBGroupsV2MessageJobFinder()
    private let reachability = Reachability.forInternetConnection()
    // This property should only be accessed on serialQueue.
    private var isDrainingQueue = false
    private var isAppInBackground = AtomicBool(false)

    private typealias BatchCompletionBlock = ([IncomingGroupsV2MessageJob], SDSAnyWriteTransaction) -> Void

    override init() {
        super.init()

        SwiftSingletons.register(self)

        observeNotifications()

        // Start processing.
        drainQueueWhenMainAppIsReady()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: NSNotification.Name.OWSApplicationWillEnterForeground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: NSNotification.Name.OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: NSNotification.Name.registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(webSocketStateDidChange),
                                               name: NSNotification.Name.webSocketStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: NSNotification.Name.reachabilityChanged,
                                               object: nil)
    }

    // MARK: - Notifications

    @objc func applicationWillEnterForeground() {
        AssertIsOnMainThread()

        isAppInBackground.set(false)
    }

    @objc func applicationDidEnterBackground() {
        AssertIsOnMainThread()

        isAppInBackground.set(true)
    }

    @objc func registrationStateDidChange() {
        AssertIsOnMainThread()

        drainQueueWhenMainAppIsReady()
    }

    @objc func webSocketStateDidChange() {
        AssertIsOnMainThread()

        drainQueueWhenMainAppIsReady()
    }

    @objc func reachabilityChanged() {
        AssertIsOnMainThread()

        drainQueueWhenMainAppIsReady()
    }

    // MARK: -

    private let serialQueue: DispatchQueue = DispatchQueue(label: "org.whispersystems.message.groupv2")

    fileprivate func enqueue(envelopeData: Data,
                             plaintextData: Data?,
                             wasReceivedByUD: Bool,
                             transaction: SDSAnyWriteTransaction) {

        // We need to persist the decrypted envelope data ASAP to prevent data loss.
        finder.addJob(envelopeData: envelopeData, plaintextData: plaintextData, wasReceivedByUD: wasReceivedByUD, transaction: transaction.unwrapGrdbWrite)
    }

    fileprivate func drainQueueWhenMainAppIsReady() {
        // GroupsV2 TODO: We'll need to reconcile the "isMainApp" checks
        // in this class with the "observe message processing"
        // changes.
        if !CurrentAppContext().isMainApp {
            return
        }
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.drainQueue()
        }
    }

    private func drainQueue() {
        guard AppReadiness.isAppReady() || CurrentAppContext().isRunningTests else {
            owsFailDebug("App is not ready.")
            return
        }
        // Don't process incoming messages in app extensions.
        //
        // GroupsV2 TODO: Reconcile with "observe message processing".
        guard CurrentAppContext().isMainApp else {
            return
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        serialQueue.async {
            guard !self.isDrainingQueue else {
                return
            }
            self.isDrainingQueue = true
            self.drainQueueWorkStep()
        }
    }

    private func drainQueueWorkStep() {
        assertOnQueue(serialQueue)

        guard !FeatureFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return
        }

        // We want a value that is just high enough to yield perf benefits.
        let kIncomingMessageBatchSize: UInt = 32
        // If the app is in the background, use batch size of 1.
        // This reduces the cost of being interrupted and rolled back if
        // app is suspended.
        let batchSize: UInt = isAppInBackground.get() ? 1 : kIncomingMessageBatchSize

        let batchJobs = databaseStorage.read { transaction in
            return self.finder.nextJobs(batchSize: batchSize, transaction: transaction.unwrapGrdbRead)
        }
        guard batchJobs.count > 0 else {
            self.isDrainingQueue = false
            Logger.verbose("Queue is drained")
            return
        }

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)")

        databaseStorage.write { outerTransaction in
            self.processJobs(jobs: batchJobs,
                             transaction: outerTransaction) { (processedJobs, completionTransaction) in
                                // NOTE: completionTransaction is the same transaction as outerTransaction
                                //       in the "sync" case but a different transaction in the "async" case.
                                let uniqueIds = processedJobs.map { $0.uniqueId }
                                self.finder.removeJobs(withUniqueIds: uniqueIds,
                                                       transaction: completionTransaction.unwrapGrdbWrite)

                                let jobCount: UInt = self.finder.jobCount(transaction: completionTransaction)

                                Logger.verbose("completed \(processedJobs.count)/\(batchJobs.count) jobs. \(jobCount) jobs left.")

                                completionTransaction.addAsyncCompletion {
                                    assert(backgroundTask != nil)
                                    backgroundTask = nil

                                    // Wait a bit in hopes of increasing the batch size.
                                    // This delay won't affect the first message to arrive when this queue is idle,
                                    // so by definition we're receiving more than one message and can benefit from
                                    // batching.
                                    self.serialQueue.asyncAfter(deadline: DispatchTime.now() + 0.5) {
                                        self.drainQueueWorkStep()
                                    }
                                }
            }
        }
    }

    private func jobInfo(forJob job: IncomingGroupsV2MessageJob,
                         transaction: SDSAnyReadTransaction) -> IncomingGroupsV2MessageJobInfo {
        var jobInfo = IncomingGroupsV2MessageJobInfo(job: job)
        guard let envelope = job.envelope else {
            owsFailDebug("Missing envelope.")
            return jobInfo
        }
        jobInfo.envelope = envelope
        guard let groupContext = GroupsV2MessageProcessor.groupContextV2(forEnvelope: envelope, plaintextData: job.plaintextData) else {
            owsFailDebug("Missing group context.")
            return jobInfo
        }
        jobInfo.groupContext = groupContext
        do {
            jobInfo.groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: groupContext.masterKey)
        } catch {
            owsFailDebug("Invalid group context: \(error).")
            return jobInfo
        }

        return jobInfo
    }

    private func canJobBeDiscarded(jobInfo: IncomingGroupsV2MessageJobInfo,
                                   ignoreIfNotLocalMember: Bool,
                                   transaction: SDSAnyReadTransaction) -> Bool {
        // We want to discard asap to avoid problems with batching.
        guard let envelope = jobInfo.envelope else {
            owsFailDebug("Missing envelope.")
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
        guard let sourceAddress = envelope.sourceAddress,
            sourceAddress.isValid else {
                owsFailDebug("Invalid source address.")
                return true
        }
        guard !blockingManager.isAddressBlocked(sourceAddress) &&
            !blockingManager.isGroupIdBlocked(groupContextInfo.groupId) else {
                Logger.info("Discarding blocked envelope.")
                return true
        }
        guard groupContext.hasRevision else {
            Logger.info("Missing revision.")
            return true
        }

        if ignoreIfNotLocalMember {
            let groupId = groupContextInfo.groupId
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                return true
            }
            guard groupThread.isLocalUserInGroup() else {
                // This could happen due to:
                //
                // * A bug.
                // * A race between message sending and leaving a group.
                //   We already know that we've left the group, but the
                //   sender didn't at the time they sent.
                // * A race between message sending and a group update.
                //   We already know that we've been kicked out of the group,
                //   but the sender didn't at the time they sent.
                return true
            }
        }
        return false
    }

    // Like non-v2 group messages, we want to do batch processing
    // wherever possible for perf reasons (to reduce view updates).
    // We should be able to mostly do that. However, there will be
    // some edge cases where we'll need to interact with the service
    // before we can process the message. Those messages should be
    // processed alone in a batch of their own.
    //
    // Therefore, when trying to process we try to take either:
    //
    // * The first N messages that can be processed "locally".
    // * The first message that has to be processed "remotely"
    private func canJobBeProcessedInLocalBatch(jobInfo: IncomingGroupsV2MessageJobInfo,
                                               transaction: SDSAnyReadTransaction) -> Bool {
        // We cannot ignoreIfNotLocalMember here because we might have been
        // added to the group and not yet know it.  We might learn of that
        // while fetching changes from the service OR while applying
        // changes embedded in the incoming message.
        if canJobBeDiscarded(jobInfo: jobInfo, ignoreIfNotLocalMember: false, transaction: transaction) {
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
        let groupId = groupContextInfo.groupId
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            return false
        }
        let messageRevision = groupContext.revision
        let modelRevision = groupThread.groupModel.groupV2Revision
        if messageRevision <= modelRevision {
            return true
        }
        // GroupsV2 TODO: Try to apply any embedded change if only
        //                missing a single revision.
        return false
    }

    // NOTE: This method might do its work synchronously (in the "local" case)
    //       or asynchronously (in the "remote" case).  It may only process
    //       a subset of the jobs.
    private func processJobs(jobs: [IncomingGroupsV2MessageJob],
                             transaction: SDSAnyWriteTransaction,
                             completion: @escaping BatchCompletionBlock) {

        // 1. Gather info for each job.
        // 2. Decide whether we'll process 1 "remote" job or N "local" jobs.
        //
        // Remote jobs require interaction with the service, namely fetching latest
        // group state.
        var isLocalBatch = true
        var jobInfos = [IncomingGroupsV2MessageJobInfo]()
        for job in jobs {
            let jobInfo = self.jobInfo(forJob: job, transaction: transaction)
            let canJobBeProcessedInLocalBatch = self.canJobBeProcessedInLocalBatch(jobInfo: jobInfo, transaction: transaction)
            if !canJobBeProcessedInLocalBatch {
                if jobInfos.count > 0 {
                    // Can't add "remote" job to "local" batch, abort and process jobs
                    // already added to batch.
                    break
                }
                // Remote batches should only contain a single job.
                isLocalBatch = false
                jobInfos.append(jobInfo)
                break
            }
            jobInfos.append(jobInfo)
        }

        if isLocalBatch {
            let processedJobs = performLocalProcessingSync(jobInfos: jobInfos,
                                                           transaction: transaction)
            completion(processedJobs, transaction)
        } else {
            assert(jobInfos.count == 1)
            guard let jobInfo = jobInfos.first else {
                owsFailDebug("Missing job")
                completion([], transaction)
                return
            }
            performRemoteProcessingAsync(jobInfo: jobInfo, completion: completion)
        }
    }

    private func performLocalProcessingSync(jobInfos: [IncomingGroupsV2MessageJobInfo],
                                            transaction: SDSAnyWriteTransaction) -> [IncomingGroupsV2MessageJob] {
        guard jobInfos.count > 0 else {
            owsFailDebug("Missing jobInfos.")
            return []
        }

        let reportFailure = { (transaction: SDSAnyWriteTransaction) in
            // TODO: Add analytics.
            let errorMessage = ThreadlessErrorMessage.corruptedMessageInUnknownThread()
            self.notificationsManager.notifyUser(for: errorMessage, transaction: transaction)
        }

        var processedJobs = [IncomingGroupsV2MessageJob]()
        for jobInfo in jobInfos {
            let job = jobInfo.job

            // GroupsV2 TODO: Try to apply embedded group changes, if any.

            // We can now ignoreIfNotLocalMember because local group state
            // should now reflect the revision at which this message was
            // sent.  If we're not a member, we can discard this message.
            if canJobBeDiscarded(jobInfo: jobInfo,
                                 ignoreIfNotLocalMember: true, transaction: transaction) {
                // Do nothing.
                Logger.verbose("Discarding job.")
            } else {
                guard let envelope = jobInfo.envelope else {
                    owsFailDebug("Missing envelope.")
                    reportFailure(transaction)
                    continue
                }
                if !self.messageManager.processEnvelope(envelope,
                                                        plaintextData: job.plaintextData,
                                                        wasReceivedByUD: job.wasReceivedByUD,
                                                        transaction: transaction) {
                    reportFailure(transaction)
                }
            }
            processedJobs.append(job)

            if isAppInBackground.get() {
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

    // Fetch group state from service and apply.
    //
    // * Try to fetch and apply incremental "changes".
    // * Failover to fetching and applying latest state.
    // * We need to distinguish between retryable (network) errors
    //   and non-retryable errors.
    // * In the case of networking errors, we should do exponential
    //   backoff.
    // * If reachability changes, we should retry network errors
    //   immediately.
    //
    // GroupsV2 TODO: Ensure comment above is implemented.
    private func performRemoteProcessingAsync(jobInfo: IncomingGroupsV2MessageJobInfo,
                                              completion: @escaping BatchCompletionBlock) {
        guard let groupContextInfo = jobInfo.groupContextInfo,
            let groupContext = jobInfo.groupContext else {
                owsFailDebug("Missing jobInfo properties.")
                databaseStorage.write { transaction in
                    completion([jobInfo.job], transaction)
                }
                return
        }
        groupsV2.fetchAndApplyGroupV2UpdatesFromServiceObjc(groupId: groupContextInfo.groupId,
                                                            groupSecretParamsData: groupContextInfo.groupSecretParamsData,
                                                            upToRevision: groupContext.revision)
            .then(on: DispatchQueue.global()) { _ in
                return self.databaseStorage.write(.promise) { transaction in
                    let processedJobs = self.performLocalProcessingSync(jobInfos: [jobInfo], transaction: transaction)
                    completion(processedJobs, transaction)
                }
        }.catch(on: .global()) { (_) in
            // GroupsV2 TODO: We need to distinguish network errors from other (un-retryable errors).
            self.databaseStorage.write { transaction in
                completion([jobInfo.job], transaction)
            }
        }.retainUntilComplete()
    }
}

// MARK: -

@objc
public class GroupsV2MessageProcessor: NSObject {
    private let processingQueue = IncomingGroupsV2MessageQueue()

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        processingQueue.drainQueueWhenMainAppIsReady()
    }

    // MARK: -

    @objc
    public func enqueue(envelopeData: Data,
                        plaintextData: Data?,
                        wasReceivedByUD: Bool,
                        transaction: SDSAnyWriteTransaction) {
        guard envelopeData.count > 0 else {
            owsFailDebug("Empty envelope.")
            return
        }

        // We need to persist the decrypted envelope data ASAP to prevent data loss.
        processingQueue.enqueue(envelopeData: envelopeData,
                                plaintextData: plaintextData,
                                wasReceivedByUD: wasReceivedByUD,
                                transaction: transaction)

        // The new envelope won't be visible to the finder until this transaction commits,
        // so drainQueue in the transaction completion.
        transaction.addAsyncCompletion {
            self.processingQueue.drainQueueWhenMainAppIsReady()
        }
    }

    @objc
    public class func isGroupsV2Message(envelope: SSKProtoEnvelope?,
                                        plaintextData: Data?) -> Bool {
        return groupContextV2(forEnvelope: envelope,
                              plaintextData: plaintextData) != nil
    }

    @objc
    public class func groupContextV2(forEnvelope envelope: SSKProtoEnvelope?,
                                     plaintextData: Data?) -> SSKProtoGroupContextV2? {
        guard let envelope = envelope else {
            return nil
        }
        guard let plaintextData = plaintextData,
            plaintextData.count > 0 else {
                return nil
        }
        guard envelope.content != nil else {
            return nil
        }

        let contentProto: SSKProtoContent
        do {
            contentProto = try SSKProtoContent.parseData(plaintextData)
        } catch {
            owsFailDebug("could not parse proto: \(error)")
            return nil
        }

        if let groupV2 = contentProto.dataMessage?.groupV2 {
            return groupV2
        } else if let groupV2 = contentProto.syncMessage?.sent?.message?.groupV2 {
            return groupV2
        } else {
            return nil
        }
    }
}
