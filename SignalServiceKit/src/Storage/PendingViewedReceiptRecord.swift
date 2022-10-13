//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct PendingViewedReceiptRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pending_viewed_receipts"

    public private(set) var id: Int64?
    public let threadId: Int64
    public let messageTimestamp: Int64
    public let messageUniqueId: String?
    public let authorPhoneNumber: String?
    public let authorUuid: String?

    public init(threadId: Int64, messageTimestamp: Int64, messageUniqueId: String?, authorPhoneNumber: String?, authorUuid: String?) {
        self.threadId = threadId
        self.messageTimestamp = messageTimestamp
        self.messageUniqueId = messageUniqueId
        self.authorPhoneNumber = authorPhoneNumber
        self.authorUuid = authorUuid
    }

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}
