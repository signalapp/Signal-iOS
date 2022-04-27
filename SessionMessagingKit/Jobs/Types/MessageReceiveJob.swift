// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionUtilitiesKit

public enum MessageReceiveJob: JobExecutor {
    public static var maxFailureCount: Int = 10
    public static var requiresThreadId: Bool = true
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData)
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        var updatedJob: Job = job
        var leastSevereError: Error?
        
        GRDBStorage.shared.write { db in
            var remainingMessagesToProcess: [Details.MessageInfo] = []
            
            for messageInfo in details.messages {
                do {
                    // Note: The main reason why the 'MessageReceiver.parse' can fail but then succeed
                    // later on is when we get a closed group message which is signed using a new key
                    // but haven't received the key yet (the key gets sent directly to the user rather
                    // than via the closed group so this is unfortunately a possible case)
                    let isRetry: Bool = (job.failureCount > 0)
                    let (message, proto) = try MessageReceiver.parse(
                        db,
                        data: messageInfo.data,
                        isRetry: isRetry
                    )
                    message.serverHash = messageInfo.serverHash
                    
                    try MessageReceiver.handle(
                        db,
                        message: message,
                        associatedWithProto: proto,
                        openGroupId: nil,
                        isBackgroundPoll: details.isBackgroundPoll
                    )
                }
                catch {
                    // We failed to process this message so add it to the list to re-process
                    remainingMessagesToProcess.append(messageInfo)
                    
                    // If the current message is a permanent failure then override it with the new error (we want
                    // to retry if there is a single non-permanent error)
                    switch leastSevereError {
                        case let error as MessageReceiverError where !error.isRetryable:
                            leastSevereError = error
                        
                        default: break
                    }
                }
            }
            
            // If any messages failed to process then we want to update the job to only include
            // those failed messages
            updatedJob = try job
                .with(
                    details: Details(
                        messages: remainingMessagesToProcess,
                        isBackgroundPoll: details.isBackgroundPoll
                    )
                )
                .defaulting(to: job)
                .saved(db)
        }
        
        }
        
        // Handle the result
        switch leastSevereError {
            case let error as MessageReceiverError where !error.isRetryable:
                SNLog("Message receive job permanently failed due to error: \(error)")
                failure(job, error, true)
                
            case .some(let error):
                SNLog("Couldn't receive message due to error: \(error)")
                failure(job, error, true)
                
            case .none:
                success(job, false)
        }
    }
}

// MARK: - MessageReceiveJob.Details

extension MessageReceiveJob {
    public struct Details: Codable {
        public struct MessageInfo: Codable {
            public let data: Data
            public let serverHash: String?
            
            public init(
                data: Data,
                serverHash: String?
            ) {
                self.data = data
                self.serverHash = serverHash
            }
        }
        
        public let messages: [MessageInfo]
        public let isBackgroundPoll: Bool
        
        public init(
            messages: [MessageInfo],
            isBackgroundPoll: Bool
        ) {
            self.messages = messages
            self.isBackgroundPoll = isBackgroundPoll
        }
    }
}
