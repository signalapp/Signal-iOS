// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

extension MessageReceiver {
    internal static func handleReadReceipt(_ db: Database, message: ReadReceipt) throws {
        guard let sender: String = message.sender else { return }
        guard let timestampMsValues: [Double] = message.timestamps?.map({ Double($0) }) else { return }
        guard let readTimestampMs: Double = message.receivedTimestamp.map({ Double($0) }) else { return }
        
        try Interaction.markAsRead(
            db,
            recipientId: sender,
            timestampMsValues: timestampMsValues,
            readTimestampMs: readTimestampMs
        )
    }
}
