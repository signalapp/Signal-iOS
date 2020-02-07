//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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

    private var groupV2Updates: GroupV2Updates {
        return SSKEnvironment.shared.groupV2Updates
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
        drainQueueWhenReady()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(webSocketStateDidChange),
                                               name: .webSocketStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: .reachabilityChanged,
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

        drainQueueWhenReady()
    }

    @objc func webSocketStateDidChange() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
    }

    @objc func reachabilityChanged() {
        AssertIsOnMainThread()

        drainQueueWhenReady()
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

    fileprivate func drainQueueWhenReady() {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
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
        guard CurrentAppContext().shouldProcessIncomingMessages else {
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

        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return
        }
        guard FeatureFlags.groupsV2IncomingMessages else {
            // Don't process this queue.
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
            NotificationCenter.default.postNotificationNameAsync(GroupsV2MessageProcessor.didFlushGroupsV2MessageQueue, object: nil)
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

        return false
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
    private func canJobBeProcessedWithoutUpdate(jobInfo: IncomingGroupsV2MessageJobInfo,
                                                transaction: SDSAnyReadTransaction) -> Bool {
        if canJobBeDiscarded(jobInfo: jobInfo, transaction: transaction) {
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
        // The incoming message indicates that there is a new group revision.
        // We'll update our group model in a standalone batch using either
        // the change proto embedded in the group context or by fetching
        // latest state from the service.
        return false
    }

    // NOTE: This method might do its work synchronously (in the "no update" case)
    //       or asynchronously (in the "update" case).  It may only process
    //       a subset of the jobs.
    private func processJobs(jobs: [IncomingGroupsV2MessageJob],
                             transaction: SDSAnyWriteTransaction,
                             completion: @escaping BatchCompletionBlock) {

        // 1. Gather info for each job.
        // 2. Decide whether we'll process 1 "update" job or N "no update" jobs.
        //
        // "Update" jobs may require interaction with the service, namely
        // fetching group changes or latest group state.
        var isUpdateBatch = false
        var jobInfos = [IncomingGroupsV2MessageJobInfo]()
        for job in jobs {
            let jobInfo = self.jobInfo(forJob: job, transaction: transaction)
            let canJobBeProcessedWithoutUpdate = self.canJobBeProcessedWithoutUpdate(jobInfo: jobInfo, transaction: transaction)
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
                completion([], transaction)
                return
            }
            updateGroupAndProcessJobAsync(jobInfo: jobInfo, completion: completion)
        } else {
            let processedJobs = performLocalProcessingSync(jobInfos: jobInfos,
                                                           transaction: transaction)
            completion(processedJobs, transaction)
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

            if canJobBeDiscarded(jobInfo: jobInfo, transaction: transaction) {
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

    private enum UpdateOutcome {
        case successShouldProcess
        case failureShouldDiscard
        case failureShouldRetry
        case failureShouldFailoverToService
    }

    private func updateGroupAndProcessJobAsync(jobInfo: IncomingGroupsV2MessageJobInfo,
                                               completion: @escaping BatchCompletionBlock) {

        firstly {
            updateGroupPromise(jobInfo: jobInfo)
        }.map(on: DispatchQueue.global()) { (updateOutcome: UpdateOutcome) throws -> Void in
            switch updateOutcome {
            case .successShouldProcess:
                self.databaseStorage.write { transaction in
                    let processedJobs = self.performLocalProcessingSync(jobInfos: [jobInfo], transaction: transaction)
                    completion(processedJobs, transaction)
                }
            case .failureShouldDiscard:
                throw GroupsV2Error.shouldDiscard
            case .failureShouldRetry:
                throw GroupsV2Error.shouldRetry
            case .failureShouldFailoverToService:
                owsFailDebug("Invalid embeddedUpdateOutcome: .failureShouldFailoverToService.")
                throw GroupsV2Error.shouldDiscard
            }
        }.recover(on: .global()) { error in
            Logger.warn("error: \(type(of: error)) \(error)")

            switch error {
            case GroupsV2Error.shouldRetry:
                // GroupsV2 TODO: We need to handle retry.
                break
            default:
                break
            }

            // Default to discarding jobs on failure.
            self.databaseStorage.write { transaction in
                completion([jobInfo.job], transaction)
            }
        }.retainUntilComplete()
    }

    private func updateGroupPromise(jobInfo: IncomingGroupsV2MessageJobInfo) -> Promise<UpdateOutcome> {

        // First, we try to update the group locally using changes embedded in
        // the group context (if any).
        return databaseStorage.write(.promise) { (transaction) -> UpdateOutcome in
            return self.tryToUpdateUsingEmbeddedGroupUpdate(jobInfo: jobInfo,
                                                            transaction: transaction)
        }.then(on: DispatchQueue.global()) { (embeddedUpdateOutcome) -> Promise<UpdateOutcome> in
            if embeddedUpdateOutcome == .failureShouldFailoverToService {
                return self.tryToUpdateUsingService(jobInfo: jobInfo)
            } else {
                return Promise.value(embeddedUpdateOutcome)
            }
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
    private func tryToUpdateUsingEmbeddedGroupUpdate(jobInfo: IncomingGroupsV2MessageJobInfo,
                                                     transaction: SDSAnyWriteTransaction) -> UpdateOutcome {
        guard let groupContextInfo = jobInfo.groupContextInfo,
            let groupContext = jobInfo.groupContext else {
                owsFailDebug("Missing jobInfo properties.")
                return .failureShouldDiscard
        }
        let groupId = groupContextInfo.groupId
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            // We might be learning of a group for the first time
            // in which case we should fetch current group state from the
            // service.
            return .failureShouldFailoverToService
        }
        let oldGroupModel = groupThread.groupModel
        guard oldGroupModel.groupsVersion == .V2 else {
            owsFailDebug("Invalid groupsVersion.")
            return .failureShouldDiscard
        }
        guard groupContext.hasRevision else {
            owsFailDebug("Missing revision.")
            return .failureShouldDiscard
        }
        let contextRevision = groupContext.revision
        guard contextRevision > oldGroupModel.groupV2Revision else {
            // Group is already updated.
            // No need to apply embedded change from the group context; it is obsolete.
            // This can happen due to races.
            return .successShouldProcess
        }
        guard contextRevision == oldGroupModel.groupV2Revision + 1 else {
            // We can only apply embedded changes if we're behind exactly
            // one revision.
            return .failureShouldFailoverToService
        }
        guard FeatureFlags.groupsV2processProtosInGroupUpdates else {
            return .failureShouldFailoverToService
        }
        guard let changeActionsProtoData = groupContext.groupChange else {
            // No embedded group change.
            return .failureShouldFailoverToService
        }
        let changeActionsProto: GroupsProtoGroupChangeActions
        do {
            // We need to verify the signature because this proto came from
            // another client, not the service.
            changeActionsProto = try groupsV2.parseAndVerifyChangeActionsProto(changeActionsProtoData,
                                                                               ignoreSignature: false)
        } catch {
            owsFailDebug("Error: \(error)")
            return .failureShouldFailoverToService
        }

        let updatedGroupThread: TSGroupThread
        do {
            updatedGroupThread = try groupV2Updates.updateGroupWithChangeActions(groupId: groupId,
                                                                                 changeActionsProto: changeActionsProto,
                                                                                 transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            // GroupsV2 TODO: Make sure this is still correct behavior.
            return .failureShouldFailoverToService
        }
        let updatedGroupModel = updatedGroupThread.groupModel

        guard updatedGroupModel.groupV2Revision >= contextRevision else {
            owsFailDebug("Invalid revision.")
            return .failureShouldFailoverToService
        }
        guard updatedGroupModel.groupV2Revision == contextRevision else {
            // We expect the embedded changes to update us to the target
            // revision.  If we update past that, assert but proceed in production.
            owsFailDebug("Unexpected revision.")
            return .successShouldProcess
        }
        Logger.info("Successfully applied embedded change proto from group context.")
        return .successShouldProcess
    }

    private func tryToUpdateUsingService(jobInfo: IncomingGroupsV2MessageJobInfo) -> Promise<UpdateOutcome> {
        guard let groupContextInfo = jobInfo.groupContextInfo,
            let groupContext = jobInfo.groupContext else {
                owsFailDebug("Missing jobInfo properties.")
                return Promise(error: GroupsV2Error.shouldDiscard)
        }
        guard let groupV2UpdatesSwift = self.groupV2Updates as? GroupV2UpdatesSwift else {
            return Promise(error: OWSAssertionError("Missing groupV2UpdatesSwift."))
        }

        // See GroupV2UpdatesImpl.
        // This will try to update the group using incremental "changes" but
        // failover to using a "snapshot".
        let groupUpdateMode = GroupUpdateMode.upToSpecificRevisionImmediately(upToRevision: groupContext.revision)
        return firstly {
            groupV2UpdatesSwift.tryToRefreshV2GroupThreadWithThrottling(groupId: groupContextInfo.groupId,
                                                                           groupSecretParamsData: groupContextInfo.groupSecretParamsData,
                                                                           groupUpdateMode: groupUpdateMode)
        }.map(on: .global()) { (_) in
            return UpdateOutcome.successShouldProcess
        }.recover(on: .global()) { error -> Guarantee<UpdateOutcome> in
            // GroupsV2 TODO: We need to distinguish network errors from other (un-retryable errors).
            Logger.warn("error: \(type(of: error)) \(error)")

            switch error {
            case let networkManagerError as NetworkManagerError:
                guard networkManagerError.isNetworkConnectivityError else {
                    return Guarantee.value(UpdateOutcome.failureShouldDiscard)
                }

                // GroupsV2 TODO: Consult networkManagerError.statusCode.
                return Guarantee.value(UpdateOutcome.failureShouldRetry)
            default:
                return Guarantee.value(UpdateOutcome.failureShouldDiscard)
            }
        }
    }

    func hasPendingJobs(transaction: SDSAnyReadTransaction) -> Bool {
        return self.finder.jobCount(transaction: transaction) > 0
    }
}

// MARK: -

@objc
public class GroupsV2MessageProcessor: NSObject {

    @objc
    public static let didFlushGroupsV2MessageQueue = Notification.Name("didFlushGroupsV2MessageQueue")

    private let processingQueue = IncomingGroupsV2MessageQueue()

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        processingQueue.drainQueueWhenReady()
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

        guard FeatureFlags.groupsV2IncomingMessages else {
            // Discard envelope.
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
            self.processingQueue.drainQueueWhenReady()
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

    @objc
    public func hasPendingJobs(transaction: SDSAnyReadTransaction) -> Bool {
        return processingQueue.hasPendingJobs(transaction: transaction)
    }
}
