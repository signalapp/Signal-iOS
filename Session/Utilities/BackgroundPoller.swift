// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionMessagingKit
import SessionUtilitiesKit

@objc(LKBackgroundPoller)
public final class BackgroundPoller : NSObject {
    private static var closedGroupPoller: ClosedGroupPoller!
    private static var promises: [Promise<Void>] = []

    private override init() { }

    @objc(pollWithCompletionHandler:)
    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        promises = []
        promises.append(pollForMessages())
        promises.append(contentsOf: pollForClosedGroupMessages())
        
        let v2OpenGroupServers = Set(Storage.shared.getAllV2OpenGroups().values.map { $0.server })
        v2OpenGroupServers.forEach { server in
            let poller = OpenGroupPollerV2(for: server)
            poller.stop()
            promises.append(poller.poll(isBackgroundPoll: true))
        }
        when(resolved: promises).done { _ in
            completionHandler(.newData)
        }.catch { error in
            SNLog("Background poll failed due to error: \(error)")
            completionHandler(.failed)
        }
    }
    
    private static func pollForMessages() -> Promise<Void> {
        let userPublicKey = getUserHexEncodedPublicKey()
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
                getMessages(for: groupPublicKey)
            }
    }
    
    private static func getMessages(for publicKey: String) -> Promise<Void> {
        return SnodeAPI.getSwarm(for: publicKey).then(on: DispatchQueue.main) { swarm -> Promise<Void> in
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
}
