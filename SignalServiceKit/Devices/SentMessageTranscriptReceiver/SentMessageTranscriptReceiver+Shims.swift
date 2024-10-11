//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension SentMessageTranscriptReceiverImpl {
    public enum Shims {
        public typealias DisappearingMessagesJob = _SentMessageTranscriptReceiver_DisappearingMessagesJobShim
        public typealias EarlyMessageManager = _SentMessageTranscriptReceiver_EarlyMessageManagerShim
        public typealias GroupManager = _SentMessageTranscriptReceiver_GroupManagerShim
        public typealias PaymentsHelper = _SentMessageTranscriptReceiver_PaymentsHelperShim
        public typealias ViewOnceMessages = _SentMessageTranscriptReceiver_ViewOnceMessagesShim
    }
    public enum Wrappers {
        public typealias DisappearingMessagesJob = _SentMessageTranscriptReceiver_DisappearingMessagesJobWrapper
        public typealias EarlyMessageManager = _SentMessageTranscriptReceiver_EarlyMessageManagerWrapper
        public typealias GroupManager = _SentMessageTranscriptReceiver_GroupManagerWrapper
        public typealias PaymentsHelper = _SentMessageTranscriptReceiver_PaymentsHelperWrapper
        public typealias ViewOnceMessages = _SentMessageTranscriptReceiver_ViewOnceMessagesWrapper
    }
}

// MARK: - DisappearingMessagesJob

public protocol _SentMessageTranscriptReceiver_DisappearingMessagesJobShim {

    func startExpiration(
        for message: TSMessage,
        expirationStartedAt: UInt64,
        tx: DBWriteTransaction
    )
}

public class _SentMessageTranscriptReceiver_DisappearingMessagesJobWrapper: _SentMessageTranscriptReceiver_DisappearingMessagesJobShim {

    public init() {}

    public func startExpiration(for message: TSMessage, expirationStartedAt: UInt64, tx: DBWriteTransaction) {
        SSKEnvironment.shared.disappearingMessagesJobRef.startAnyExpiration(
            for: message,
            expirationStartedAt: expirationStartedAt,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: - EarlyMessageManager

public protocol _SentMessageTranscriptReceiver_EarlyMessageManagerShim {

    func applyPendingMessages(
        for message: TSMessage,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    )
}

public class _SentMessageTranscriptReceiver_EarlyMessageManagerWrapper: _SentMessageTranscriptReceiver_EarlyMessageManagerShim {

    private let earlyMessageManager: EarlyMessageManager

    public init(_ earlyMessageManager: EarlyMessageManager) {
        self.earlyMessageManager = earlyMessageManager
    }

    public func applyPendingMessages(for message: TSMessage, localIdentifiers: LocalIdentifiers, tx: DBWriteTransaction) {
        earlyMessageManager.applyPendingMessages(for: message, localIdentifiers: localIdentifiers, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - GroupManager

public protocol _SentMessageTranscriptReceiver_GroupManagerShim {

    func remoteUpdateDisappearingMessages(
        withContactThread thread: TSContactThread,
        disappearingMessageToken: VersionedDisappearingMessageToken,
        changeAuthor: Aci,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    )
}

public class _SentMessageTranscriptReceiver_GroupManagerWrapper: _SentMessageTranscriptReceiver_GroupManagerShim {

    public init() {}

    public func remoteUpdateDisappearingMessages(
        withContactThread thread: TSContactThread,
        disappearingMessageToken: VersionedDisappearingMessageToken,
        changeAuthor: Aci,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        GroupManager.remoteUpdateDisappearingMessages(
            contactThread: thread,
            disappearingMessageToken: disappearingMessageToken,
            changeAuthor: changeAuthor,
            localIdentifiers: localIdentifiers,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: - Payments Helper

public protocol _SentMessageTranscriptReceiver_PaymentsHelperShim {

    func processReceivedTranscriptPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        messageTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

public class _SentMessageTranscriptReceiver_PaymentsHelperWrapper: _SentMessageTranscriptReceiver_PaymentsHelperShim {

    private let paymentsHelper: PaymentsHelper

    public init(_ paymentsHelper: PaymentsHelper) {
        self.paymentsHelper = paymentsHelper
    }

    public func processReceivedTranscriptPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        messageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        paymentsHelper.processReceivedTranscriptPaymentNotification(
            thread: thread,
            paymentNotification: paymentNotification,
            messageTimestamp: messageTimestamp,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: - ViewOnceMessages

public protocol _SentMessageTranscriptReceiver_ViewOnceMessagesShim {

    func markAsComplete(
        message: TSMessage,
        sendSyncMessages: Bool,
        tx: DBWriteTransaction
    )
}

public class _SentMessageTranscriptReceiver_ViewOnceMessagesWrapper: _SentMessageTranscriptReceiver_ViewOnceMessagesShim {

    public init() {}

    public func markAsComplete(message: TSMessage, sendSyncMessages: Bool, tx: DBWriteTransaction) {
        ViewOnceMessages.markAsComplete(message: message, sendSyncMessages: sendSyncMessages, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
