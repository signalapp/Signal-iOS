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
    public static let defaultLabel = "IncomingGroupSync"

    override class var jobRecordType: JobRecordType { .deprecated_incomingGroupSync }

    #if TESTABLE_BUILD

    init(
        attachmentId: String,
        label: String,
        exclusiveProcessIdentifier: String?,
        failureCount: UInt,
        status: Status
    ) {
        self.attachmentId = attachmentId
        super.init(
            label: label,
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    #endif

    public let attachmentId: String

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attachmentId = try container.decode(String.self, forKey: .attachmentId)
        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try super.encode(to: container.superEncoder())
        try container.encode(attachmentId, forKey: .attachmentId)
    }
}
