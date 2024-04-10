//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Job record for processing an incoming group sync message.
///
/// These sync messages are long-since deprecated, and support has been removed.
/// This class remains to facilitate cleaning up any currently-persisted
/// records, although it is unlikely any still exist.
public final class IncomingGroupSyncJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .deprecated_incomingGroupSync }

    #if TESTABLE_BUILD

    init(
        legacyAttachmentId: String,
        exclusiveProcessIdentifier: String?,
        failureCount: UInt,
        status: Status
    ) {
        self.legacyAttachmentId = legacyAttachmentId
        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    #endif

    public let legacyAttachmentId: String

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        legacyAttachmentId = try container.decode(String.self, forKey: .legacyAttachmentId)
        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try super.encode(to: container.superEncoder())
        try container.encode(legacyAttachmentId, forKey: .legacyAttachmentId)
    }
}
