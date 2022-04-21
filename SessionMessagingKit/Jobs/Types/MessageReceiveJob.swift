// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionUtilitiesKit

public enum MessageReceiveJob: JobExecutor {
    public static var maxFailureCount: UInt = 10
    public static var requiresThreadId: Bool = true
    
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
        
        var processingError: Error?
        
        GRDBStorage.shared.write { db in
            do {
                let isRetry: Bool = (job.failureCount > 0)
                let (message, proto) = try MessageReceiver.parse(
                    db,
                    data: details.data,
                    isRetry: isRetry
                )
                message.serverHash = details.serverHash
                
                try MessageReceiver.handle(
                    db,
                    message: message,
                    associatedWithProto: proto,
                    openGroupId: nil,
                    isBackgroundPoll: details.isBackgroundPoll
                )
            }
            catch {
                processingError = error
            }
        }
        
        // Handle the result
        switch processingError {
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
        public let data: Data
        public let serverHash: String?
        public let isBackgroundPoll: Bool
    }
}
