//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class NoopPendingReadReceiptRecorder: NSObject, PendingReadReceiptRecorder {
    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) {
        Logger.info("")
    }
}
