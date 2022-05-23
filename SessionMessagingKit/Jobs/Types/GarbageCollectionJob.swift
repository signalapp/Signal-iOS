// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit
import SessionUtilitiesKit
import SessionSnodeKit

public enum GarbageCollectionJob: JobExecutor {
    public static var maxFailureCount: Int = 10
    public static var requiresThreadId: Bool = true
    public static let requiresInteractionId: Bool = false   // Some messages don't have interactions
    
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
        
        failure(job, JobRunnerError.missingRequiredDetails, true)
    }
}

// MARK: - GarbageCollectionJob.Details

extension GarbageCollectionJob {
    public enum Types: Codable, CaseIterable {
        case oldOpenGroupMessages
        case expiredControlMessageProcessRecords
        case threadTypingIndicators
        case orphanedAttachmentFiles
        case orphanedProfileAvatars
    }
    
    public struct Details: Codable {
        public let typesToCollect: [Types]
        
        public init(typesToCollect: [Types] = Types.allCases) {
            self.typesToCollect = typesToCollect
        }
    }
}
