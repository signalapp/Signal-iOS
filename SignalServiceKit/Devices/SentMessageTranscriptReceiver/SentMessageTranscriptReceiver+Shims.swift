//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension SentMessageTranscriptReceiverImpl {
    public enum Shims {
        public typealias EarlyMessageManager = _SentMessageTranscriptReceiver_EarlyMessageManagerShim
        public typealias GroupManager = _SentMessageTranscriptReceiver_GroupManagerShim
        public typealias ViewOnceMessages = _SentMessageTranscriptReceiver_ViewOnceMessagesShim
    }

    public enum Wrappers {
        public typealias EarlyMessageManager = _SentMessageTranscriptReceiver_EarlyMessageManagerWrapper
        public typealias GroupManager = _SentMessageTranscriptReceiver_GroupManagerWrapper
        public typealias ViewOnceMessages = _SentMessageTranscriptReceiver_ViewOnceMessagesWrapper
    }
}

// MARK: - EarlyMessageManager

public protocol _SentMessageTranscriptReceiver_EarlyMessageManagerShim {

    func applyPendingMessages(
        for message: TSMessage,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    )
}

public class _SentMessageTranscriptReceiver_EarlyMessageManagerWrapper: _SentMessageTranscriptReceiver_EarlyMessageManagerShim {

    private let earlyMessageManager: EarlyMessageManager

    public init(_ earlyMessageManager: EarlyMessageManager) {
        self.earlyMessageManager = earlyMessageManager
    }

    public func applyPendingMessages(for message: TSMessage, localIdentifiers: LocalIdentifiers, tx: DBWriteTransaction) {
        earlyMessageManager.applyPendingMessages(for: message, localIdentifiers: localIdentifiers, transaction: tx)
    }
}

// MARK: - GroupManager

public protocol _SentMessageTranscriptReceiver_GroupManagerShim {

    func remoteUpdateDisappearingMessages(
        withContactThread thread: TSContactThread,
        disappearingMessageToken: VersionedDisappearingMessageToken,
        changeAuthor: Aci,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    )
}

public class _SentMessageTranscriptReceiver_GroupManagerWrapper: _SentMessageTranscriptReceiver_GroupManagerShim {

    public init() {}

    public func remoteUpdateDisappearingMessages(
        withContactThread thread: TSContactThread,
        disappearingMessageToken: VersionedDisappearingMessageToken,
        changeAuthor: Aci,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        GroupManager.remoteUpdateDisappearingMessages(
            contactThread: thread,
            disappearingMessageToken: disappearingMessageToken,
            changeAuthor: changeAuthor,
            localIdentifiers: localIdentifiers,
            transaction: tx,
        )
    }
}

// MARK: - ViewOnceMessages

public protocol _SentMessageTranscriptReceiver_ViewOnceMessagesShim {

    func markAsComplete(
        message: TSMessage,
        sendSyncMessages: Bool,
        tx: DBWriteTransaction,
    )
}

public class _SentMessageTranscriptReceiver_ViewOnceMessagesWrapper: _SentMessageTranscriptReceiver_ViewOnceMessagesShim {

    public init() {}

    public func markAsComplete(message: TSMessage, sendSyncMessages: Bool, tx: DBWriteTransaction) {
        ViewOnceMessages.markAsComplete(message: message, sendSyncMessages: sendSyncMessages, transaction: tx)
    }
}
