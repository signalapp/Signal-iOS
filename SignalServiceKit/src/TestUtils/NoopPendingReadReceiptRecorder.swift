//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class NoopPendingReceiptRecorder: NSObject, PendingReceiptRecorder {
    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) {
        Logger.info("")
    }

    public func recordPendingViewedReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) {
        Logger.info("")
    }
}
