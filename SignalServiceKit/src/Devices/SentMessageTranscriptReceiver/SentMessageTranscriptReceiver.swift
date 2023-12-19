//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Processes "outgoing message" notifications from linked devices,
/// creating the local TSOutgoingMessage.
public protocol SentMessageTranscriptReceiver {

    func process(
        _ sentMessageTranscript: SentMessageTranscript,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    )
}
