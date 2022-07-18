// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionMessagingKit
import SessionUtilitiesKit

public final class BackgroundPoller {
    private static var promises: [Promise<Void>] = []

    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        promises = []
            .appending(pollForMessages())
            .appending(contentsOf: pollForClosedGroupMessages())
            .appending(
                contentsOf: Storage.shared
                    .read { db in
                        // The default room promise creates an OpenGroup with an empty `roomToken` value,
                        // we don't want to start a poller for this as the user hasn't actually joined a room
                        try OpenGroup
                            .select(.server)
                            .filter(OpenGroup.Columns.roomToken != "")
                            .filter(OpenGroup.Columns.isActive)
                            .distinct()
                            .asRequest(of: String.self)
                            .fetchSet(db)
                    }
                    .defaulting(to: [])
                    .map { server in
                        let poller: OpenGroupAPI.Poller = OpenGroupAPI.Poller(for: server)
                        poller.stop()
                        
                        return poller.poll(isBackgroundPoll: true, isPostCapabilitiesRetry: false)
                    }
            )
        
        // Background tasks will automatically be terminated after 30 seconds (which results in a crash
        // and a prompt to appear for the user) we want to avoid this so we start a timer which expires
        // after 25 seconds allowing us to cancel all pending promises
        let cancelTimer: Timer = Timer.scheduledTimerOnMainThread(withTimeInterval: 25, repeats: false) { timer in
            timer.invalidate()
            
            guard promises.contains(where: { !$0.isResolved }) else { return }
            
            SNLog("Background poll failed due to manual timeout")
            completionHandler(.failed)
        }
        
        when(resolved: promises)
            .done { _ in
                cancelTimer.invalidate()
                completionHandler(.newData)
            }
            .catch { error in
                // If we have already invalidated the timer then do nothing (we essentially timed out)
                guard cancelTimer.isValid else { return }
                
                SNLog("Background poll failed due to error: \(error)")
                cancelTimer.invalidate()
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
        return Storage.shared
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
                ClosedGroupPoller.poll(
                    groupPublicKey,
                    on: DispatchQueue.main,
                    maxRetryCount: 0,
                    isBackgroundPoll: true
                )
            }
    }
    
    private static func getMessages(for publicKey: String) -> Promise<Void> {
        return SnodeAPI.getSwarm(for: publicKey)
            .then(on: DispatchQueue.main) { swarm -> Promise<Void> in
                guard let snode = swarm.randomElement() else { throw SnodeAPIError.generic }
                
                return SnodeAPI.getMessages(from: snode, associatedWith: publicKey)
                    .then(on: DispatchQueue.main) { messages -> Promise<Void> in
                        guard !messages.isEmpty else { return Promise.value(()) }
                        
                        var jobsToRun: [Job] = []
                        
                        Storage.shared.write { db in
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
                                    
                                    // Add to the JobRunner so they are persistent and will retry on
                                    // the next app run if they fail
                                    JobRunner.add(db, job: job, canStartJob: false)
                                    jobsToRun.append(job)
                                }
                        }
                        
                        let promises: [Promise<Void>] = jobsToRun.map { job -> Promise<Void> in
                            let (promise, seal) = Promise<Void>.pending()
                            
                            // Note: In the background we just want jobs to fail silently
                            MessageReceiveJob.run(
                                job,
                                queue: DispatchQueue.main,
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
