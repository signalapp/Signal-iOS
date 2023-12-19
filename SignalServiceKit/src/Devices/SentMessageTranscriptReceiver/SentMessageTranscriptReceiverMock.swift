//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class SentMessageTranscriptReceiverMock: SentMessageTranscriptReceiver {

    public init() {}

    public func process(
        _: SentMessageTranscript,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }
}

#endif
