// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import Sodium
import SessionSnodeKit

@objc(LKPoller)
public final class Poller : NSObject {
    private let storage = OWSPrimaryStorage.shared()
    private var isPolling: Atomic<Bool> = Atomic(false)
    private var usedSnodes = Set<Snode>()
    private var pollCount = 0

    // MARK: - Settings
    
    private static let pollInterval: TimeInterval = 1.5
    private static let retryInterval: TimeInterval = 0.25
    /// After polling a given snode this many times we always switch to a new one.
    ///
    /// The reason for doing this is that sometimes a snode will be giving us successful responses while
    /// it isn't actually getting messages from other snodes.
    private static let maxPollCount: UInt = 6

    // MARK: - Error
    
    private enum Error : LocalizedError {
        case pollLimitReached

        var localizedDescription: String {
            switch self {
                case .pollLimitReached: return "Poll limit reached for current snode."
            }
        }
    }

    // MARK: - Public API
    
    @objc public func startIfNeeded() {
        guard !isPolling.wrappedValue else { return }
        
        SNLog("Started polling.")
        isPolling.mutate { $0 = true }
        setUpPolling()
    }

    @objc public func stop() {
        SNLog("Stopped polling.")
        isPolling.mutate { $0 = false }
        usedSnodes.removeAll()
    }

    // MARK: - Private API
    
    private func setUpPolling() {
        guard isPolling.wrappedValue else { return }
        
        Threading.pollerQueue.async {
            let _ = SnodeAPI.getSwarm(for: getUserHexEncodedPublicKey())
                .then(on: Threading.pollerQueue) { [weak self] _ -> Promise<Void> in
                    let (promise, seal) = Promise<Void>.pending()
                    
                    self?.usedSnodes.removeAll()
                    self?.pollNextSnode(seal: seal)
                    
                    return promise
                }
                .ensure(on: Threading.pollerQueue) { [weak self] in // Timers don't do well on background queues
                    guard self?.isPolling.wrappedValue == true else { return }
                    
                    Timer.scheduledTimerOnMainThread(withTimeInterval: Poller.retryInterval, repeats: false) { _ in
                        self?.setUpPolling()
                    }
                }
        }
    }

    private func pollNextSnode(seal: Resolver<Void>) {
        let userPublicKey = getUserHexEncodedPublicKey()
        let swarm = SnodeAPI.swarmCache[userPublicKey] ?? []
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
        
        let userPublicKey = getUserHexEncodedPublicKey()
        
        return SnodeAPI.getMessages(from: snode, associatedWith: userPublicKey)
            .then(on: Threading.pollerQueue) { [weak self] messages -> Promise<Void> in
                guard self?.isPolling.wrappedValue == true else { return Promise { $0.fulfill(()) } }
                
                if !messages.isEmpty {
                    var messageCount: Int = 0
                    
                    GRDBStorage.shared.write { db in
                        var threadMessages: [String: [MessageReceiveJob.Details.MessageInfo]] = [:]
                        
                        messages.forEach { message in
                            guard let envelope = SNProtoEnvelope.from(message) else { return }
                            
                            // Extract the threadId and add that to the messageReceive job for
                            // multi-threading and garbage collection purposes
                            let threadId: String? = MessageReceiver.extractSenderPublicKey(db, from: envelope)
                            
                            if threadId == nil {
                                // TODO: I assume a configuration message doesn't need a 'threadId' (confirm this and set the 'requiresThreadId' requirement accordingly)
                                // TODO: Does the configuration message come through here????
                                print("RAWR WHAT CASES LETS THIS BE NIL????")
                            }
                            
                            do {
                                let serialisedData: Data = try envelope.serializedData()
                                _ = try message.info.inserted(db)
                                
                                // Ignore hashes for messages we have previously handled
                                guard try SnodeReceivedMessageInfo.filter(SnodeReceivedMessageInfo.Columns.hash == message.info.hash).fetchCount(db) == 1 else {
                                    throw MessageReceiverError.duplicateMessage
                                }
                                
                                threadMessages[threadId ?? ""] = (threadMessages[threadId ?? ""] ?? [])
                                    .appending(
                                        MessageReceiveJob.Details.MessageInfo(
                                            data: serialisedData,
                                            serverHash: message.info.hash,
                                            serverExpirationTimestamp: (TimeInterval(message.info.expirationDateMs) / 1000)
                                        )
                                    )
                            }
                            catch {
                                switch error {
                                    // Ignore duplicate messages
                                    case .SQLITE_CONSTRAINT_UNIQUE, MessageReceiverError.duplicateMessage: break
                                        
                                    default:
                                        SNLog("Failed to deserialize envelope due to error: \(error).")
                                }
                            }
                        }
                        
                        messageCount = threadMessages
                            .values
                            .reduce(into: 0) { prev, next in prev += next.count }
                        
                        threadMessages.forEach { threadId, threadMessages in
                            JobRunner.add(
                                db,
                                job: Job(
                                    variant: .messageReceive,
                                    behaviour: .runOnce,
                                    threadId: threadId,
                                    details: MessageReceiveJob.Details(
                                        messages: threadMessages,
                                        isBackgroundPoll: false
                                    )
                                )
                            )
                        }
                    }
                    
                    SNLog("Received \(messageCount) message(s).")
                }
                
                self?.pollCount += 1
                
                guard (self?.pollCount ?? 0) < Poller.maxPollCount else {
                    throw Error.pollLimitReached
                }
                
                return withDelay(Poller.pollInterval, completionQueue: Threading.pollerQueue) {
                    guard let strongSelf = self, strongSelf.isPolling.wrappedValue else { return Promise { $0.fulfill(()) } }
                    
                    return strongSelf.poll(snode, seal: longTermSeal)
                }
            }
    }
}
