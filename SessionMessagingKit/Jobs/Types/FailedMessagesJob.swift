// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public enum FailedMessagesJob: JobExecutor {
    public static let maxFailureCount: UInt = 0
    public static let requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        // Update all 'sending' message states to 'failed'
        GRDBStorage.shared.write { db in
            let changeCount: Int = try RecipientState
                .filter(RecipientState.Columns.state == RecipientState.State.sending)
                .updateAll(db, RecipientState.Columns.state.set(to: RecipientState.State.failed))
        
            Logger.debug("Marked \(changeCount) messages as failed")
        }
        
        success(job, false)
    }
}
