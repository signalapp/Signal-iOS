//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Processes "outgoing message" notifications from linked devices,
/// creating the local TSOutgoingMessage.
public protocol SentMessageTranscriptReceiver {

    /// - returns The message created or updated by the transcript, after being inserted in the database.
    /// Can be nil if the transcript doesn't affect a visible message, e.g. the transcript is an end session update.
    /// Note that not all transcripts result in the creation of a message.
    /// Its theoretically possible for more than one existing message to match the transcript (e.g. in the case
    /// of a recipient update), but this method only returns one message. That should never happen in practice.
    @discardableResult
    func process(
        _ sentMessageTranscript: SentMessageTranscript,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) -> Swift.Result<TSOutgoingMessage?, Error>
}
