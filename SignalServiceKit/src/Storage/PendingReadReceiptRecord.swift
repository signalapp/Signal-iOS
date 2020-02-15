//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public struct PendingReadReceiptRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pending_read_receipts"

    public private(set) var id: Int64?
    public let threadId: Int64
    public let messageTimestamp: Int64
    public let authorPhoneNumber: String?
    public let authorUuid: String?

    public init(threadId: Int64, messageTimestamp: Int64, authorPhoneNumber: String?, authorUuid: String?) {
        self.threadId = threadId
        self.messageTimestamp = messageTimestamp
        self.authorPhoneNumber = authorPhoneNumber
        self.authorUuid = authorUuid
    }

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}
