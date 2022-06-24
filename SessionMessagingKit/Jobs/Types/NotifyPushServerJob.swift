// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public enum NotifyPushServerJob: JobExecutor {
    public static var maxFailureCount: Int = 20
    public static var requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
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
        
        let requestBody: RequestBody = RequestBody(
            data: details.message.data.description,
            sendTo: details.message.recipient
        )
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            failure(job, HTTP.Error.invalidJSON, true)
            return
        }
        
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [ Header.contentType.rawValue: "application/json" ]
        request.httpBody = body
        
        attempt(maxRetryCount: 4, recoveringOn: queue) {
            OnionRequestAPI
                .sendOnionRequest(
                    request,
                    to: server,
                    using: .v2,
                    with: PushNotificationAPI.serverPublicKey
                )
                .map { _ in }
        }
        .done(on: queue) { _ in success(job, false) }
        .catch(on: queue) { error in failure(job, error, false) }
        .retainUntilComplete()
    }
}

// MARK: - NotifyPushServerJob.Details

extension NotifyPushServerJob {
    public struct Details: Codable {
        public let message: SnodeMessage
    }
    
    struct RequestBody: Codable {
        enum CodingKeys: String, CodingKey {
            case data
            case sendTo = "send_to"
        }
        
        let data: String
        let sendTo: String
    }
}
