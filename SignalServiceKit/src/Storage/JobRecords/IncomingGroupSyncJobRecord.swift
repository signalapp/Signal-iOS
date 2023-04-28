//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class IncomingGroupSyncJobRecord: JobRecord, FactoryInitializableFromRecordType {
    public static let defaultLabel = "IncomingGroupSync"

    override class var jobRecordType: JobRecordType { .incomingGroupSync }

    public let attachmentId: String

    public init(
        attachmentId: String,
        label: String,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.attachmentId = attachmentId

        super.init(
            label: label,
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

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
