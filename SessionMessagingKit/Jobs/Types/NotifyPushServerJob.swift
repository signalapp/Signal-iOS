// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public enum NotifyPushServerJob: JobExecutor {
    public static var maxFailureCount: UInt = 20
    public static var requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        let server: String = PushNotificationAPI.server
        
        guard
            let url: URL = URL(string: "\(server)/notify"),
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData)
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        let parameters: JSON = [
            "data": details.message.data.description,
            "send_to": details.message.recipient
        ]
        
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [
            "Content-Type": "application/json"
        ]
        
        attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI
                .sendOnionRequest(
                    request,
                    to: server,
                    target: "/loki/v2/lsrpc",
                    using: PushNotificationAPI.serverPublicKey
                )
                .map { _ in }
        }
        .done { _ in
            success(job, false)
        }
        .`catch` { error in
            failure(job, error, false)
        }
        .retainUntilComplete()
    }
}

// MARK: - NotifyPushServerJob.Details

extension NotifyPushServerJob {
    public struct Details: Codable {
        public let message: SnodeMessage
    }
}
