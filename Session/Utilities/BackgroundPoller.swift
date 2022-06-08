// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionMessagingKit
import SessionUtilitiesKit

@objc(LKBackgroundPoller)
public final class BackgroundPoller: NSObject {
    private static var promises: [Promise<Void>] = []

    private override init() { }

    @objc(pollWithCompletionHandler:)
    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        promises = []
            .appending(pollForMessages())
            .appending(pollForClosedGroupMessages())
            .appending(
                GRDBStorage.shared
                    .read { db in try OpenGroup.fetchAll(db) }
                    .defaulting(to: [])
                    .map { openGroup -> String in openGroup.server }
                    .asSet()
                    .map { server in
                        let poller: OpenGroupAPI.Poller = OpenGroupAPI.Poller(for: server)
                        poller.stop()
                        
                        return poller.poll(isBackgroundPoll: true)
                    }
            )
        
        when(resolved: promises)
            .done { _ in
                completionHandler(.newData)
            }
            .catch { error in
                SNLog("Background poll failed due to error: \(error)")
                completionHandler(.failed)
            }
    }
    
    private static func pollForMessages() -> Promise<Void> {
        let userPublicKey: String = getUserHexEncodedPublicKey()
        return getMessages(for: userPublicKey)
    }
    
    private static func pollForClosedGroupMessages() -> [Promise<Void>] {
        // Fetch all closed groups (excluding any don't contain the current user as a
        // GroupMemeber as the user is no longer a member of those)
        return GRDBStorage.shared
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
            .map { groupPublicKey in
                getClosedGroupMessages(for: groupPublicKey)
            }
    }
    
    private static func getMessages(for publicKey: String) -> Promise<Void> {
        return SnodeAPI.getSwarm(for: publicKey)
            .then(on: DispatchQueue.main) { swarm -> Promise<Void> in
                guard let snode = swarm.randomElement() else { throw SnodeAPI.Error.generic }
                
                return attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.main) {
                    return SnodeAPI.getMessages(from: snode, associatedWith: publicKey)
                        .then(on: DispatchQueue.main) { messages -> Promise<Void> in
                            guard !messages.isEmpty else { return Promise.value(()) }
                            
                            var jobsToRun: [Job] = []
                            
                            GRDBStorage.shared.write { db in
                                var threadMessages: [String: [MessageReceiveJob.Details.MessageInfo]] = [:]
                                
                                messages.forEach { message in
                                    do {
                                        let processedMessage: ProcessedMessage? = try Message.processRawReceivedMessage(db, rawMessage: message)
                                        let key: String = (processedMessage?.threadId ?? Message.nonThreadMessageId)
                                        
                                        threadMessages[key] = (threadMessages[key] ?? [])
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
                                
                                threadMessages
                                    .forEach { threadId, threadMessages in
                                        let maybeJob: Job? = Job(
                                            variant: .messageReceive,
                                            behaviour: .runOnce,
                                            threadId: threadId,
                                            details: MessageReceiveJob.Details(
                                                messages: threadMessages,
                                                isBackgroundPoll: true
                                            )
                                        )
                                        
                                        guard let job: Job = maybeJob else { return }
                                        
                                        JobRunner.add(db, job: job)
                                        jobsToRun.append(job)
                                    }
                            }
                            
                            let promises = jobsToRun.compactMap { job -> Promise<Void>? in
                                let (promise, seal) = Promise<Void>.pending()
                                
                                // Note: In the background we just want jobs to fail silently
                                MessageReceiveJob.run(
                                    job,
                                    success: { _, _ in seal.fulfill(()) },
                                    failure: { _, _, _ in seal.fulfill(()) },
                                    deferred: { _ in seal.fulfill(()) }
                                )

                                return promise
                            }

                            return when(fulfilled: promises)
                        }
                }
            }
    }
    
    private static func getClosedGroupMessages(for publicKey: String) -> Promise<Void> {
        return SnodeAPI.getSwarm(for: publicKey)
            .then(on: DispatchQueue.main) { swarm -> Promise<Void> in
                guard let snode = swarm.randomElement() else { throw SnodeAPI.Error.generic }
            
                return attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.main) {
                    var promises: [Promise<Data>] = []
                    var namespaces: [Int] = []
                
                    // We have to poll for both namespace 0 and -10 when hardfork == 19 && softfork == 0
                    if SnodeAPI.hardfork <= 19, SnodeAPI.softfork == 0 {
                        let promise = SnodeAPI.getRawClosedGroupMessagesFromDefaultNamespace(from: snode, associatedWith: publicKey)
                        promises.append(promise)
                        namespaces.append(SnodeAPI.defaultNamespace)
                    }
                
                    if SnodeAPI.hardfork >= 19 && SnodeAPI.softfork >= 0 {
                        let promise = SnodeAPI.getRawMessages(from: snode, associatedWith: publicKey, authenticated: false)
                        promises.append(promise)
                        namespaces.append(SnodeAPI.closedGroupNamespace)
                    }
                
                    return when(resolved: promises)
                        .then(on: DispatchQueue.main) { results -> Promise<Void> in
                            var promises: [Promise<Void>] = []
                            var index = 0
                    
                            for result in results {
                                if case .fulfilled(let messages) = result {
                                    guard !messages.isEmpty else { return Promise.value(()) }
                                    
                                    var jobsToRun: [Job] = []
                                    
                                    GRDBStorage.shared.write { db in
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
                                        
                                        let maybeJob: Job? = Job(
                                            variant: .messageReceive,
                                            behaviour: .runOnce,
                                            threadId: groupPublicKey,
                                            details: MessageReceiveJob.Details(
                                                messages: jobDetailMessages,
                                                isBackgroundPoll: true
                                            )
                                        )
                                        
                                        guard let job: Job = maybeJob else { return }
                                        
                                        JobRunner.add(db, job: job)
                                        jobsToRun.append(job)
                                    }
                                    
                                    let (promise, seal) = Promise<Void>.pending()
                                    
                                    // Note: In the background we just want jobs to fail silently
                                    MessageReceiveJob.run(
                                        job,
                                        success: { _, _ in seal.fulfill(()) },
                                        failure: { _, _, _ in seal.fulfill(()) },
                                        deferred: { _ in seal.fulfill(()) }
                                    )

                                    promises.append(promise)
                                }
                        
                                index += 1
                            }
                            
                            return when(fulfilled: promises) // The promise returned by MessageReceiveJob never rejects
                        }
                }
            }
    }
}
