//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class OWSMockSyncManager: SyncManager {
    public func sendConfigurationSyncMessage(tx: DBWriteTransaction) {
        Logger.info("")
    }

    public func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: TimeInterval) -> Promise<[String]> {
        Logger.info("")

        return Promise.value([])
    }

    public func sendAllSyncRequestMessagesIfNecessary() -> Promise<Void> {
        Logger.info("")

        return Promise.value(())
    }

    public func sendAllSyncRequestMessages(timeout: TimeInterval) -> Promise<Void> {
        Logger.info("")

        return Promise.value(())
    }

    public func sendFetchLatestProfileSyncMessage(tx: DBWriteTransaction) {
        Logger.info("")
    }

    public func sendFetchLatestStorageManifestSyncMessage(tx: DBWriteTransaction) {
        Logger.info("")
    }

    public func sendFetchLatestSubscriptionStatusSyncMessage(tx: DBWriteTransaction) {
        Logger.info("")
    }

    public func sendKeysSyncMessage(tx: DBWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingFetchLatestSyncMessage(_ syncMessage: SSKProtoSyncMessageFetchLatest, transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func sendKeysSyncRequestMessage(transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        timestamp: UInt64,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        Logger.info("")
    }

    public func sendMessageRequestResponseSyncMessage(
        forThread thread: TSThread,
        timestamp: UInt64,
        responseType: OutgoingMessageRequestResponseSyncMessage.ResponseType,
        tx: DBWriteTransaction,
    ) {
        Logger.info("")
    }

    public func syncAllContacts() async throws {
        Logger.info("")
    }

    public func syncAllContactsIfFullSyncRequested() async throws {
        Logger.info("")
    }
}

#endif
