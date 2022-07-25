// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public enum FailedMessageSendsJob: JobExecutor {
    public static let maxFailureCount: Int = -1
    public static let requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        // Update all 'sending' message states to 'failed'
        Storage.shared.write { db in
            let changeCount: Int = try RecipientState
                .filter(RecipientState.Columns.state == RecipientState.State.sending)
                .updateAll(db, RecipientState.Columns.state.set(to: RecipientState.State.failed))
            let attachmentChangeCount: Int = try Attachment
                .filter(Attachment.Columns.state == Attachment.State.uploading)
                .updateAll(db, Attachment.Columns.state.set(to: Attachment.State.failedUpload))
            
            SNLog("Marked \(changeCount) message\(changeCount == 1 ? "" : "s") as failed (\(attachmentChangeCount) upload\(attachmentChangeCount == 1 ? "" : "s") cancelled)")
        }
        
        success(job, false)
    }
}
