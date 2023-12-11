//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class SessionResetJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .sessionReset }

    public let contactThreadId: String

    init(
        contactThreadId: String,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.contactThreadId = contactThreadId

        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    public convenience init(contactThread: TSContactThread) {
        self.init(contactThreadId: contactThread.uniqueId)
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        contactThreadId = try container.decode(String.self, forKey: .contactThreadId)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(contactThreadId, forKey: .contactThreadId)
    }
}
