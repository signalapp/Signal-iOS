// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
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
                    // Note: It generally shouldn't be possible for 'MessageReceiver.parse' to fail
                    // the main situation where this can happen is when the jobs run out of order (eg.
                    // a closed group message encrypted with a new key gets processed before the key
                    // gets added - this shouldn't be as possible with the updated JobRunner)
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
                    switch error {
                        // Note: This is the same as the 'MessageReceiverError.duplicateMessage'
                        // which is not retryable so just skip to the next message to process
                        case DatabaseError.SQLITE_CONSTRAINT_UNIQUE:
                            SNLog("MessageReceiveJob skipping duplicate message.")
                            continue
                            
                        default: break
                    }
                    
                    // If the current message is a permanent failure then override it with the
                    // new error (we want to retry if there is a single non-permanent error)
                    switch error {
                        case let receiverError as MessageReceiverError where !receiverError.isRetryable:
                            SNLog("MessageReceiveJob permanently failed message due to error: \(error)")
                            continue
                        
                        default:
                            SNLog("Couldn't receive message due to error: \(error)")
                            leastSevereError = error
                            
                            // We failed to process this message but it is a retryable error
                            // so add it to the list to re-process
                            remainingMessagesToProcess.append(messageInfo)
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
        
        // Handle the result
        switch leastSevereError {
            case let error as MessageReceiverError where !error.isRetryable:
                failure(updatedJob, error, true)
                
            case .some(let error):
                failure(updatedJob, error, false)
                
            case .none:
                success(updatedJob, false)
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
