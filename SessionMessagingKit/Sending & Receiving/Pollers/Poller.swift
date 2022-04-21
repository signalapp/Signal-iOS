// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium
import SessionSnodeKit

@objc(LKPoller)
public final class Poller : NSObject {
    private let storage = OWSPrimaryStorage.shared()
    private var isPolling = false
    private var usedSnodes = Set<Snode>()
    private var pollCount = 0

    // MARK: Settings
    private static let pollInterval: TimeInterval = 1.5
    private static let retryInterval: TimeInterval = 0.25
    /// After polling a given snode this many times we always switch to a new one.
    ///
    /// The reason for doing this is that sometimes a snode will be giving us successful responses while
    /// it isn't actually getting messages from other snodes.
    private static let maxPollCount: UInt = 6

    // MARK: Error
    private enum Error : LocalizedError {
        case pollLimitReached

        var localizedDescription: String {
            switch self {
            case .pollLimitReached: return "Poll limit reached for current snode."
            }
        }
    }

    // MARK: Public API
    @objc public func startIfNeeded() {
        guard !isPolling else { return }
        SNLog("Started polling.")
        isPolling = true
        setUpPolling()
    }

    @objc public func stop() {
        SNLog("Stopped polling.")
        isPolling = false
        usedSnodes.removeAll()
    }

    // MARK: Private API
    private func setUpPolling() {
        guard isPolling else { return }
        Threading.pollerQueue.async {
            let _ = SnodeAPI.getSwarm(for: getUserHexEncodedPublicKey()).then(on: Threading.pollerQueue) { [weak self] _ -> Promise<Void> in
                guard let strongSelf = self else { return Promise { $0.fulfill(()) } }
                strongSelf.usedSnodes.removeAll()
                let (promise, seal) = Promise<Void>.pending()
                strongSelf.pollNextSnode(seal: seal)
                return promise
            }.ensure(on: Threading.pollerQueue) { [weak self] in // Timers don't do well on background queues
                guard let strongSelf = self, strongSelf.isPolling else { return }
                Timer.scheduledTimerOnMainThread(withTimeInterval: Poller.retryInterval, repeats: false) { _ in
                    guard let strongSelf = self else { return }
                    strongSelf.setUpPolling()
                }
            }
        }
        
    }

    private func pollNextSnode(seal: Resolver<Void>) {
        let userPublicKey = getUserHexEncodedPublicKey()
        let swarm = SnodeAPI.swarmCache[userPublicKey] ?? []
        let unusedSnodes = swarm.subtracting(usedSnodes)
        if !unusedSnodes.isEmpty {
            // randomElement() uses the system's default random generator, which is cryptographically secure
            let nextSnode = unusedSnodes.randomElement()!
            usedSnodes.insert(nextSnode)
            poll(nextSnode, seal: seal).done2 {
                seal.fulfill(())
            }.catch2 { [weak self] error in
                if let error = error as? Error, error == .pollLimitReached {
                    self?.pollCount = 0
                } else {
                    SNLog("Polling \(nextSnode) failed; dropping it and switching to next snode.")
                    SnodeAPI.dropSnodeFromSwarmIfNeeded(nextSnode, publicKey: userPublicKey)
                }
                Threading.pollerQueue.async {
                    self?.pollNextSnode(seal: seal)
                }
            }
        } else {
            seal.fulfill(())
        }
    }

    private func poll(_ snode: Snode, seal longTermSeal: Resolver<Void>) -> Promise<Void> {
        guard isPolling else { return Promise { $0.fulfill(()) } }
        let userPublicKey = getUserHexEncodedPublicKey()
        return SnodeAPI.getRawMessages(from: snode, associatedWith: userPublicKey)
            .then(on: Threading.pollerQueue) { [weak self] rawResponse -> Promise<Void> in
                guard let strongSelf = self, strongSelf.isPolling else { return Promise { $0.fulfill(()) } }
                
                let messages: [SnodeReceivedMessage] = SnodeAPI.parseRawMessagesResponse(rawResponse, from: snode, associatedWith: userPublicKey)
                
                if !messages.isEmpty {
                    SNLog("Received \(messages.count) new message(s).")
                    
                    GRDBStorage.shared.write { db in
                        messages.forEach { message in
                            guard let envelope = SNProtoEnvelope.from(message) else { return }
                            
                            // Extract the sender public key (used as the threadId in contact threads) and add
                            // that to the messageReceive job for multi-threading and garbage collection purposes
                            //
                            // Note: This is a slightly optimised version of the message decryption which
                            // just skips the validation (handled when the job actually runs) and doesn't throw
                            let threadId: String? = MessageReceiver.extractSenderPublicKey(db, from: envelope)
                            
                            if threadId == nil {
                            }
                            
                            do {
                                JobRunner.add(
                                    db,
                                    job: Job(
                                        variant: .messageReceive,
                                        behaviour: .runOnce,
                                        threadId: threadId,
                                        details: MessageReceiveJob.Details(
                                            data: try envelope.serializedData(),
                                            serverHash: message.info.hash,
                                            isBackgroundPoll: false
                                        )
                                    )
                                )
                                
                                // Persist the received message after the MessageReceiveJob is created
                                try message.info.save(db)
                            }
                            catch {
                                SNLog("Failed to deserialize envelope due to error: \(error).")
                            }
                        }
                    }
                }
                
                strongSelf.pollCount += 1
                
                guard strongSelf.pollCount < Poller.maxPollCount else {
                    throw Error.pollLimitReached
                }
                
                return withDelay(Poller.pollInterval, completionQueue: Threading.pollerQueue) {
                    guard let strongSelf = self, strongSelf.isPolling else { return Promise { $0.fulfill(()) } }
                    return strongSelf.poll(snode, seal: longTermSeal)
                }
            }
    }
}
