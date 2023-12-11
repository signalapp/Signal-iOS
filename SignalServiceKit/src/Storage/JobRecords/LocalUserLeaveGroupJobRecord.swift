//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public final class LocalUserLeaveGroupJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .localUserLeaveGroup }

    let threadId: String
    let replacementAdminAciString: String?
    let waitForMessageProcessing: Bool

    init(
        threadId: String,
        replacementAdminAci: Aci?,
        waitForMessageProcessing: Bool,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.threadId = threadId
        self.replacementAdminAciString = replacementAdminAci?.serviceIdUppercaseString
        self.waitForMessageProcessing = waitForMessageProcessing

        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        threadId = try container.decode(String.self, forKey: .threadId)
        replacementAdminAciString = try container.decodeIfPresent(String.self, forKey: .replacementAdminAciString)
        waitForMessageProcessing = try container.decode(Bool.self, forKey: .waitForMessageProcessing)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(threadId, forKey: .threadId)
        try container.encodeIfPresent(replacementAdminAciString, forKey: .replacementAdminAciString)
        try container.encode(waitForMessageProcessing, forKey: .waitForMessageProcessing)
    }
}
