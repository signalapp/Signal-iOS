//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages the BGProcessingTask for doing the backfill of attachments that were
/// validated using an old version of the validator and need revalidation.
public class AttachmentValidationBackfillRunner: BGProcessingTaskRunner {

    // MARK: - BGProcessingTaskRunner

    // TODO: add migrator class
    public typealias Migrator = Void
    public typealias Store = Void

    public static let taskIdentifier = "AttachmentValidationBackfillMigrator"

    public static let requiresNetworkConnectivity = false

    public static let logger = PrefixedLogger(prefix: "AttachmentValidationBackfillMigrator")

    public static func runNextBatch(migrator: Migrator) async throws -> Bool {
        // TODO: run migration
        return true
    }

    public static func shouldLaunchBGProcessingTask(store: Store, db: SDSDatabaseStorage) -> Bool {
        // TODO: check eligibility
        return false
    }
}
