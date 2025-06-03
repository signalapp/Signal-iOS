//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public actor BackgroundMessageFetcher {
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
}
