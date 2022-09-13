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

    public func stopAllPollers() {
        let pollers: [String] = Array(isPolling.wrappedValue.keys)
        
        pollers.forEach { groupPublicKey in
            self.stopPolling(for: groupPublicKey)
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
        calledFromBackgroundPoller: Bool = false,
        isBackgroundPollValid: @escaping (() -> Bool) = { true },
        poller: ClosedGroupPoller? = nil
    ) -> Promise<Void> {
        let promise: Promise<Void> = SnodeAPI.getSwarm(for: groupPublicKey)
            .then(on: queue) { swarm -> Promise<Void> in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                guard let snode = swarm.randomElement() else { return Promise(error: Error.insufficientSnodes) }
                
                return attempt(maxRetryCount: maxRetryCount, recoveringOn: queue) {
                    guard
                        (calledFromBackgroundPoller && isBackgroundPollValid()) ||
                        poller?.isPolling.wrappedValue[groupPublicKey] == true
                    else { return Promise(error: Error.pollingCanceled) }
                    
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
                            guard
                                (calledFromBackgroundPoller && isBackgroundPollValid()) ||
                                poller?.isPolling.wrappedValue[groupPublicKey] == true
                            else { return Promise.value(()) }
                            
                            var promises: [Promise<Void>] = []
                            var jobToRun: Job? = nil
                            let allMessages: [SnodeReceivedMessage] = messageResults
                                .reduce([]) { result, next in
                                    switch next {
                                        case .fulfilled(let messages): return result.appending(contentsOf: messages)
                                        default: return result
                                    }
                                }
                            var messageCount: Int = 0
                            
                            // No need to do anything if there are no messages
                            guard !allMessages.isEmpty else {
                                if !calledFromBackgroundPoller {
                                    SNLog("Received no new messages in closed group with public key: \(groupPublicKey)")
                                }
                                return Promise.value(())
                            }
                            
                            // Otherwise process the messages and add them to the queue for handling
                            Storage.shared.write { db in
                                let processedMessages: [ProcessedMessage] = allMessages
                                    .compactMap { message -> ProcessedMessage? in
                                        do {
                                            return try Message.processRawReceivedMessage(db, rawMessage: message)
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
                                                    
                                                // In the background ignore 'SQLITE_ABORT' (it generally means
                                                // the BackgroundPoller has timed out
                                                case DatabaseError.SQLITE_ABORT:
                                                    guard !calledFromBackgroundPoller else { break }
                                                    
                                                    SNLog("Failed to the database being suspended (running in background with no background task).")
                                                    break

                                                default: SNLog("Failed to deserialize envelope due to error: \(error).")
                                            }

                                            return nil
                                        }
                                    }
                                
                                messageCount = processedMessages.count
                                
                                jobToRun = Job(
                                    variant: .messageReceive,
                                    behaviour: .runOnce,
                                    threadId: groupPublicKey,
                                    details: MessageReceiveJob.Details(
                                        messages: processedMessages.map { $0.messageInfo },
                                        calledFromBackgroundPoller: calledFromBackgroundPoller
                                    )
                                )

                                // If we are force-polling then add to the JobRunner so they are persistent and will retry on
                                // the next app run if they fail but don't let them auto-start
                                JobRunner.add(db, job: jobToRun, canStartJob: !calledFromBackgroundPoller)
                            }
                            
                            if calledFromBackgroundPoller {
                                // We want to try to handle the receive jobs immediately in the background
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
                            else {
                                SNLog("Received \(messageCount) new message\(messageCount == 1 ? "" : "s") in closed group with public key: \(groupPublicKey) (duplicates: \(allMessages.count - messageCount))")
                            }
                            
                            return when(fulfilled: promises)
                        }
                }
            }
        
        if !calledFromBackgroundPoller {
            promise.catch2 { error in
                SNLog("Polling failed for closed group with public key: \(groupPublicKey) due to error: \(error).")
            }
        }
        
        return promise
    }
}
