// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import Sodium
import SessionSnodeKit
import SessionUtilitiesKit

public final class Poller {
    private var isPolling: Atomic<Bool> = Atomic(false)
    private var usedSnodes = Set<Snode>()
    private var pollCount = 0

    // MARK: - Settings
    
    private static let pollInterval: TimeInterval = 1.5
    private static let retryInterval: TimeInterval = 0.25
    private static let maxRetryInterval: TimeInterval = 15
    
    /// After polling a given snode this many times we always switch to a new one.
    ///
    /// The reason for doing this is that sometimes a snode will be giving us successful responses while
    /// it isn't actually getting messages from other snodes.
    private static let maxPollCount: UInt = 6

    // MARK: - Error
    
    private enum Error: LocalizedError {
        case pollLimitReached

        var localizedDescription: String {
            switch self {
                case .pollLimitReached: return "Poll limit reached for current snode."
            }
        }
    }

    // MARK: - Public API
    
    public init() {}
    
    public func startIfNeeded() {
        guard !isPolling.wrappedValue else { return }
        
        SNLog("Started polling.")
        isPolling.mutate { $0 = true }
        setUpPolling()
    }

    public func stop() {
        SNLog("Stopped polling.")
        isPolling.mutate { $0 = false }
        usedSnodes.removeAll()
    }

    // MARK: - Private API
    
    private func setUpPolling(delay: TimeInterval = Poller.retryInterval) {
        guard isPolling.wrappedValue else { return }
        
        Threading.pollerQueue.async {
            let _ = SnodeAPI.getSwarm(for: getUserHexEncodedPublicKey())
                .then(on: Threading.pollerQueue) { [weak self] _ -> Promise<Void> in
                    let (promise, seal) = Promise<Void>.pending()
                    
                    self?.usedSnodes.removeAll()
                    self?.pollNextSnode(seal: seal)
                    
                    return promise
                }
                .done(on: Threading.pollerQueue) { [weak self] in
                    guard self?.isPolling.wrappedValue == true else { return }
                    
                    Timer.scheduledTimerOnMainThread(withTimeInterval: Poller.retryInterval, repeats: false) { _ in
                        self?.setUpPolling()
                    }
                }
                .catch(on: Threading.pollerQueue) { [weak self] _ in
                    guard self?.isPolling.wrappedValue == true else { return }
                    
                    let nextDelay: TimeInterval = min(Poller.maxRetryInterval, (delay * 1.2))
                    Timer.scheduledTimerOnMainThread(withTimeInterval: nextDelay, repeats: false) { _ in
                        self?.setUpPolling()
                    }
                }
        }
    }

    private func pollNextSnode(seal: Resolver<Void>) {
        let userPublicKey = getUserHexEncodedPublicKey()
        let swarm = SnodeAPI.swarmCache.wrappedValue[userPublicKey] ?? []
        let unusedSnodes = swarm.subtracting(usedSnodes)
        
        guard !unusedSnodes.isEmpty else {
            seal.fulfill(())
            return
        }
        
        // randomElement() uses the system's default random generator, which is cryptographically secure
        let nextSnode = unusedSnodes.randomElement()!
        usedSnodes.insert(nextSnode)
        
        poll(nextSnode, seal: seal)
            .done2 {
                seal.fulfill(())
            }
            .catch2 { [weak self] error in
                if let error = error as? Error, error == .pollLimitReached {
                    self?.pollCount = 0
                }
                else if UserDefaults.sharedLokiProject?[.isMainAppActive] != true {
                    // Do nothing when an error gets throws right after returning from the background (happens frequently)
                }
                else {
                    SNLog("Polling \(nextSnode) failed; dropping it and switching to next snode.")
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(nextSnode, publicKey: userPublicKey)
                }
                
                Threading.pollerQueue.async {
                    self?.pollNextSnode(seal: seal)
                }
            }
    }

    private func poll(_ snode: Snode, seal longTermSeal: Resolver<Void>) -> Promise<Void> {
        guard isPolling.wrappedValue else { return Promise { $0.fulfill(()) } }
        
        let userPublicKey: String = getUserHexEncodedPublicKey()
        
        return SnodeAPI.getMessages(from: snode, associatedWith: userPublicKey)
            .then(on: Threading.pollerQueue) { [weak self] messages -> Promise<Void> in
                guard self?.isPolling.wrappedValue == true else { return Promise { $0.fulfill(()) } }
                
                if !messages.isEmpty {
                    var messageCount: Int = 0
                    
                    Storage.shared.write { db in
                        messages
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
                                            
                                        case DatabaseError.SQLITE_ABORT:
                                            SNLog("Failed to the database being suspended (running in background with no background task).")
                                            break

                                        default: SNLog("Failed to deserialize envelope due to error: \(error).")
                                    }
                                    
                                    return nil
                                }
                            }
                            .grouped { threadId, _, _ in (threadId ?? Message.nonThreadMessageId) }
                            .forEach { threadId, threadMessages in
                                messageCount += threadMessages.count
                                
                                JobRunner.add(
                                    db,
                                    job: Job(
                                        variant: .messageReceive,
                                        behaviour: .runOnce,
                                        threadId: threadId,
                                        details: MessageReceiveJob.Details(
                                            messages: threadMessages.map { $0.messageInfo },
                                            calledFromBackgroundPoller: false
                                        )
                                    )
                                )
                            }
                    }
                    
                    SNLog("Received \(messageCount) new message\(messageCount == 1 ? "" : "s") (duplicates:  \(messages.count - messageCount))")
                }
                else {
                    SNLog("Received no new messages")
                }
                
                self?.pollCount += 1
                
                guard (self?.pollCount ?? 0) < Poller.maxPollCount else {
                    throw Error.pollLimitReached
                }
                
                return withDelay(Poller.pollInterval, completionQueue: Threading.pollerQueue) {
                    guard let strongSelf = self, strongSelf.isPolling.wrappedValue else {
                        return Promise { $0.fulfill(()) }
                    }
                    
                    return strongSelf.poll(snode, seal: longTermSeal)
                }
            }
    }
}
