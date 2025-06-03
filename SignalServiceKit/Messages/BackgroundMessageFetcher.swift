//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct BackgroundMessageFetcherFactory {
    private let chatConnectionManager: any ChatConnectionManager
    private let groupMessageProcessorManager: GroupMessageProcessorManager
    private let messageFetcherJob: MessageFetcherJob
    private let messageProcessor: MessageProcessor
    private let messageSender: MessageSender
    private let receiptSender: ReceiptSender

    public init(
        chatConnectionManager: any ChatConnectionManager,
        groupMessageProcessorManager: GroupMessageProcessorManager,
        messageFetcherJob: MessageFetcherJob,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        receiptSender: ReceiptSender,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.groupMessageProcessorManager = groupMessageProcessorManager
        self.messageFetcherJob = messageFetcherJob
        self.messageProcessor = messageProcessor
        self.messageSender = messageSender
        self.receiptSender = receiptSender
    }

    public func buildFetcher() -> BackgroundMessageFetcher {
        return BackgroundMessageFetcher(
            chatConnectionManager: self.chatConnectionManager,
            groupMessageProcessorManager: self.groupMessageProcessorManager,
            messageFetcherJob: self.messageFetcherJob,
            messageProcessor: self.messageProcessor,
            messageSender: self.messageSender,
            receiptSender: self.receiptSender,
        )
    }
}

public actor BackgroundMessageFetcher {
    private let chatConnectionManager: any ChatConnectionManager
    private let groupMessageProcessorManager: GroupMessageProcessorManager
    private let messageFetcherJob: MessageFetcherJob
    private let messageProcessor: MessageProcessor
    private let messageSender: MessageSender
    private let receiptSender: ReceiptSender

    fileprivate init(
        chatConnectionManager: any ChatConnectionManager,
        groupMessageProcessorManager: GroupMessageProcessorManager,
        messageFetcherJob: MessageFetcherJob,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        receiptSender: ReceiptSender,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.groupMessageProcessorManager = groupMessageProcessorManager
        self.messageFetcherJob = messageFetcherJob
        self.messageProcessor = messageProcessor
        self.messageSender = messageSender
        self.receiptSender = receiptSender
    }

    private var connectionTokens = [OWSChatConnection.ConnectionToken]()

    public func start() async {
        self.connectionTokens = chatConnectionManager.requestConnections()
        await self.groupMessageProcessorManager.startAllProcessors()
    }

    public func reset() {
        self.connectionTokens.forEach { $0.releaseConnection() }
        self.connectionTokens = []
    }

    public func waitForFetchingProcessingAndSideEffects() async throws {
        try await withCooperativeRace(
            { try await self._waitForFetchingProcessingAndSideEffects() },
            {
                try await self.chatConnectionManager.waitUntilIdentifiedConnectionShouldBeClosed()
                // We wanted to wait for things to happen, but we can't wait, so throw.
                throw OWSGenericError("Should be closed.")
            },
        )
    }

    private func _waitForFetchingProcessingAndSideEffects() async throws {
        try await messageProcessor.waitForFetchingAndProcessing()

        // Wait for these in parallel.
        do {
            // Wait until all ACKs are complete.
            async let pendingAcks: Void = self.messageFetcherJob.waitForPendingAcks()
            // Wait until all outgoing receipt sends are complete.
            async let pendingReceipts: Void = self.receiptSender.waitForPendingReceipts()
            // Wait until all outgoing messages are sent.
            async let pendingMessages: Void = self.messageSender.waitForPendingMessages()
            // Wait until all sync requests are fulfilled.
            async let pendingOps: Void = MessageReceiver.waitForPendingTasks()

            try await pendingAcks
            try await pendingReceipts
            try await pendingMessages
            try await pendingOps
        }

        // Finally, wait for any notifications to finish posting
        try await NotificationPresenterImpl.waitForPendingNotifications()
    }

    public func stopAndWaitBeforeSuspending() async {
        // Release the connections and wait for them to close.
        self.reset()
        await chatConnectionManager.waitForDisconnectIfClosed()

        // Wait for notifications that are already scheduled to be posted.
        do {
            try await NotificationPresenterImpl.waitForPendingNotifications()
        } catch {
            owsFailDebug("\(error)")
        }
    }
}
