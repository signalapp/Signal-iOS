//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit

final class CallLinkUpdateMessageSender {
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(messageSenderJobQueue: MessageSenderJobQueue) {
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func sendCallLinkUpdateMessage(
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        let localThread = TSContactThread.getOrCreateLocalThread(localIdentifiers: localIdentifiers, tx: tx)
        let callLinkUpdate = OutgoingCallLinkUpdateMessage(
            localThread: localThread,
            rootKey: rootKey,
            adminPasskey: adminPasskey,
            tx: tx,
        )
        messageSenderJobQueue.add(message: .preprepared(transientMessageWithoutAttachments: callLinkUpdate), transaction: tx)
    }
}
