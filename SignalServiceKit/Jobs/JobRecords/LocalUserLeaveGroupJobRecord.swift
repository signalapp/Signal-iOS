//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public final class LocalUserLeaveGroupJobRecord: JobRecord {
    override public class var jobRecordType: JobRecordType { .localUserLeaveGroup }

    let threadId: String
    let replacementAdminAciString: String?
    let waitForMessageProcessing: Bool

    init(
        threadId: String,
        replacementAdminAci: Aci?,
        waitForMessageProcessing: Bool,
        failureCount: UInt = 0,
        status: Status = .ready,
    ) {
        self.threadId = threadId
        self.replacementAdminAciString = replacementAdminAci?.serviceIdUppercaseString
        self.waitForMessageProcessing = waitForMessageProcessing

        super.init(
            failureCount: failureCount,
            status: status,
        )
    }

    required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        threadId = try container.decode(String.self, forKey: .threadId)
        replacementAdminAciString = try container.decodeIfPresent(String.self, forKey: .replacementAdminAciString)
        waitForMessageProcessing = try container.decode(Bool.self, forKey: .waitForMessageProcessing)

        try super.init(inheritableDecoder: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encodeIfPresent(replacementAdminAciString, forKey: .replacementAdminAciString)
        try container.encode(waitForMessageProcessing, forKey: .waitForMessageProcessing)
    }
}
