//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class IncomingContactSyncJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .incomingContactSync }

    public let legacyAttachmentId: String?
    public let isCompleteContactSync: Bool

    public init(
        legacyAttachmentId: String?,
        isCompleteContactSync: Bool,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.legacyAttachmentId = legacyAttachmentId
        self.isCompleteContactSync = isCompleteContactSync

        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        legacyAttachmentId = try container.decodeIfPresent(String.self, forKey: .legacyAttachmentId)
        isCompleteContactSync = try container.decode(Bool.self, forKey: .isCompleteContactSync)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encodeIfPresent(legacyAttachmentId, forKey: .legacyAttachmentId)
        try container.encode(isCompleteContactSync, forKey: .isCompleteContactSync)
    }
}
