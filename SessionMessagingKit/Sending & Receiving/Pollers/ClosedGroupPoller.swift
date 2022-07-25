// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public final class ClosedGroupPoller {
    private var isPolling: Atomic<[String: Bool]> = Atomic([:])
    private var timers: [String: Timer] = [:]

    // MARK: - Settings
    
    private static let minPollInterval: Double = 2
    private static let maxPollInterval: Double = 30

    // MARK: - Error
    
    private enum Error: LocalizedError {
        case insufficientSnodes
        case pollingCanceled

        internal var errorDescription: String? {
            switch self {
                case .insufficientSnodes: return "No snodes left to poll."
                case .pollingCanceled: return "Polling canceled."
            }
        }
    }

    // MARK: - Initialization
    
    public static let shared = ClosedGroupPoller()

    // MARK: - Public API
    
    @objc public func start() {
        // Fetch all closed groups (excluding any don't contain the current user as a
        // GroupMemeber as the user is no longer a member of those)
        Storage.shared
            .read { db in
                try ClosedGroup
                    .select(.threadId)
                    .joining(
                        required: ClosedGroup.members
                            .filter(GroupMember.Columns.profileId == getUserHexEncodedPublicKey(db))
                    )
                    .asRequest(of: String.self)
                    .fetchAll(db)
            }
            .defaulting(to: [])
            .forEach { [weak self] groupPublicKey in
                self?.startPolling(for: groupPublicKey)
            }
    }

    public func startPolling(for groupPublicKey: String) {
        guard isPolling.wrappedValue[groupPublicKey] != true else { return }
        
        // Might be a race condition that the setUpPolling finishes too soon,
        // and the timer is not created, if we mark the group as is polling
        // after setUpPolling. So the poller may not work, thus misses messages.
        isPolling.mutate { $0[groupPublicKey] = true }
        setUpPolling(for: groupPublicKey)
    }

    @objc public func stop() {
        Storage.shared
            .read { db in
                try ClosedGroup
                    .select(.threadId)
                    .asRequest(of: String.self)
                    .fetchAll(db)
            }
            .defaulting(to: [])
            .forEach { [weak self] groupPublicKey in
                self?.stopPolling(for: groupPublicKey)
            }
    }

    public func stopPolling(for groupPublicKey: String) {
        isPolling.mutate { $0[groupPublicKey] = false }
        timers[groupPublicKey]?.invalidate()
    }

    // MARK: - Private API
    
    private func setUpPolling(for groupPublicKey: String) {
        Threading.pollerQueue.async {
            ClosedGroupPoller.poll(groupPublicKey, poller: self)
                .done(on: Threading.pollerQueue) { [weak self] _ in
                    self?.pollRecursively(groupPublicKey)
                }
                .catch(on: Threading.pollerQueue) { [weak self] error in
                    // The error is logged in poll(_:)
                    self?.pollRecursively(groupPublicKey)
                }
        }
    }

    private func pollRecursively(_ groupPublicKey: String) {
        guard
            isPolling.wrappedValue[groupPublicKey] == true,
            let thread: SessionThread = Storage.shared.read({ db in try SessionThread.fetchOne(db, id: groupPublicKey) })
        else { return }
        
        // Get the received date of the last message in the thread. If we don't have any messages yet, pick some
        // reasonable fake time interval to use instead
        
        let lastMessageDate: Date = Storage.shared
            .read { db in
                try thread
                    .interactions
                    .select(.receivedAtTimestampMs)
                    .order(Interaction.Columns.timestampMs.desc)
                    .asRequest(of: Int64.self)
                    .fetchOne(db)
            }
            .map { receivedAtTimestampMs -> Date? in
                guard receivedAtTimestampMs > 0 else { return nil }
                
                return Date(timeIntervalSince1970: (TimeInterval(receivedAtTimestampMs) / 1000))
            }
            .defaulting(to: Date().addingTimeInterval(-5 * 60))
        
        let timeSinceLastMessage: TimeInterval = Date().timeIntervalSince(lastMessageDate)
        let minPollInterval: Double = ClosedGroupPoller.minPollInterval
        let limit: Double = (12 * 60 * 60)
        let a = (ClosedGroupPoller.maxPollInterval - minPollInterval) / limit
        let nextPollInterval = a * min(timeSinceLastMessage, limit) + minPollInterval
        SNLog("Next poll interval for closed group with public key: \(groupPublicKey) is \(nextPollInterval) s.")
        
        timers[groupPublicKey] = Timer.scheduledTimerOnMainThread(withTimeInterval: nextPollInterval, repeats: false) { [weak self] timer in
            timer.invalidate()
            
            Threading.pollerQueue.async {
                ClosedGroupPoller.poll(groupPublicKey, poller: self)
                    .done(on: Threading.pollerQueue) { _ in
                        self?.pollRecursively(groupPublicKey)
                    }
                    .catch(on: Threading.pollerQueue) { error in
                        // The error is logged in poll(_:)
                        self?.pollRecursively(groupPublicKey)
                    }
            }
        }
    }
    
    public static func poll(
        _ groupPublicKey: String,
        on queue: DispatchQueue = SessionSnodeKit.Threading.workQueue,
        maxRetryCount: UInt = 0,
        isBackgroundPoll: Bool = false,
        poller: ClosedGroupPoller? = nil
    ) -> Promise<Void> {
        let promise: Promise<Void> = SnodeAPI.getSwarm(for: groupPublicKey)
            .then(on: queue) { swarm -> Promise<Void> in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                guard let snode = swarm.randomElement() else { return Promise(error: Error.insufficientSnodes) }
                
                return attempt(maxRetryCount: maxRetryCount, recoveringOn: queue) {
                    guard isBackgroundPoll || poller?.isPolling.wrappedValue[groupPublicKey] == true else {
                        return Promise(error: Error.pollingCanceled)
                    }
                    
                    let promises: [Promise<[SnodeReceivedMessage]>] = {
                        if SnodeAPI.hardfork >= 19 && SnodeAPI.softfork >= 1 {
                            return [ SnodeAPI.getMessages(from: snode, associatedWith: groupPublicKey, authenticated: false) ]
                        }
                        
                        if SnodeAPI.hardfork >= 19 {
                            return [
                                SnodeAPI.getClosedGroupMessagesFromDefaultNamespace(from: snode, associatedWith: groupPublicKey),
                                SnodeAPI.getMessages(from: snode, associatedWith: groupPublicKey, authenticated: false)
                            ]
                        }
                        
                        return [ SnodeAPI.getClosedGroupMessagesFromDefaultNamespace(from: snode, associatedWith: groupPublicKey) ]
                    }()
                    
                    return when(resolved: promises)
                        .then(on: queue) { messageResults -> Promise<Void> in
                            guard isBackgroundPoll || poller?.isPolling.wrappedValue[groupPublicKey] == true else { return Promise.value(()) }
                            
                            var promises: [Promise<Void>] = []
                            var messageCount: Int = 0
                            let totalMessagesCount: Int = messageResults
                                .map { result -> Int in
                                    switch result {
                                        case .fulfilled(let messages): return messages.count
                                        default: return 0
                                    }
                                }
                                .reduce(0, +)
                            
                            messageResults.forEach { result in
                                guard case .fulfilled(let messages) = result else { return }
                                guard !messages.isEmpty else { return }
                                
                                var jobToRun: Job?
                                
                                Storage.shared.write { db in
                                    var jobDetailMessages: [MessageReceiveJob.Details.MessageInfo] = []
                                    
                                    messages.forEach { message in
                                        do {
                                            let processedMessage: ProcessedMessage? = try Message.processRawReceivedMessage(db, rawMessage: message)
                                            
                                            jobDetailMessages = jobDetailMessages
                                                .appending(processedMessage?.messageInfo)
                                        }
                                        catch {
                                            switch error {
                                                // Ignore duplicate & selfSend message errors (and don't bother logging
                                                // them as there will be a lot since we each service node duplicates messages)
                                                case DatabaseError.SQLITE_CONSTRAINT_UNIQUE,
                                                    MessageReceiverError.duplicateMessage,
                                                    MessageReceiverError.duplicateControlMessage,
                                                    MessageReceiverError.selfSend:
                                                    break
                                                
                                                default: SNLog("Failed to deserialize envelope due to error: \(error).")
                                            }
                                        }
                                    }
                                    
                                    messageCount += jobDetailMessages.count
                                    jobToRun = Job(
                                        variant: .messageReceive,
                                        behaviour: .runOnce,
                                        threadId: groupPublicKey,
                                        details: MessageReceiveJob.Details(
                                            messages: jobDetailMessages,
                                            isBackgroundPoll: isBackgroundPoll
                                        )
                                    )
                                    
                                    // If we are force-polling then add to the JobRunner so they are persistent and will retry on
                                    // the next app run if they fail but don't let them auto-start
                                    JobRunner.add(db, job: jobToRun, canStartJob: !isBackgroundPoll)
                                }
                                
                                // We want to try to handle the receive jobs immediately in the background
                                if isBackgroundPoll {
                                    promises = promises.appending(
                                        jobToRun.map { job -> Promise<Void> in
                                            let (promise, seal) = Promise<Void>.pending()
                                            
                                            // Note: In the background we just want jobs to fail silently
                                            MessageReceiveJob.run(
                                                job,
                                                queue: queue,
                                                success: { _, _ in seal.fulfill(()) },
                                                failure: { _, _, _ in seal.fulfill(()) },
                                                deferred: { _ in seal.fulfill(()) }
                                            )

                                            return promise
                                        }
                                    )
                                }
                            }
                            
                            if !isBackgroundPoll {
                                if totalMessagesCount > 0 {
                                    SNLog("Received \(messageCount) new message\(messageCount == 1 ? "" : "s") in closed group with public key: \(groupPublicKey) (duplicates: \(totalMessagesCount - messageCount))")
                                }
                                else {
                                    SNLog("Received no new messages in closed group with public key: \(groupPublicKey)")
                                }
                            }
                            
                            return when(fulfilled: promises)
                        }
                }
            }
        
        if !isBackgroundPoll {
            promise.catch2 { error in
                SNLog("Polling failed for closed group with public key: \(groupPublicKey) due to error: \(error).")
            }
        }
        
        return promise
    }
}
