//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class SessionResetJobRecord: JobRecord {
    override public class var jobRecordType: JobRecordType { .sessionReset }

    public let contactThreadId: String

    init(
        contactThreadId: String,
        failureCount: UInt = 0,
        status: Status = .ready,
    ) {
        self.contactThreadId = contactThreadId

        super.init(
            failureCount: failureCount,
            status: status,
        )
    }

    public convenience init(contactThread: TSContactThread) {
        self.init(contactThreadId: contactThread.uniqueId)
    }

    required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contactThreadId = try container.decode(String.self, forKey: .contactThreadId)
        try super.init(inheritableDecoder: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contactThreadId, forKey: .contactThreadId)
    }
}
