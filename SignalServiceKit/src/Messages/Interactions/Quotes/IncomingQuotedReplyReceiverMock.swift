//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class IncomingQuotedReplyReceiverMock: IncomingQuotedReplyReceiver {

    public init() {}

    open func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> QuotedMessageBuilder? {
        return nil
    }
}

#endif
