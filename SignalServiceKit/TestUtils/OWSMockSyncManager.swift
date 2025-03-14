//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class OWSMockSyncManager: SyncManagerProtocol {
    public func sendConfigurationSyncMessage() {
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

    public func sendFetchLatestStorageManifestSyncMessage() async {
        Logger.info("")
    }

    public func sendFetchLatestSubscriptionStatusSyncMessage() {
        Logger.info("")
    }

    public func sendKeysSyncMessage() {
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

    public func processIncomingMessageRequestResponseSyncMessage(_ syncMessage: SSKProtoSyncMessageMessageRequestResponse, transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType) {
        Logger.info("")
    }

    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType, transaction: DBWriteTransaction) {
        Logger.info("")
    }

    public func syncAllContacts() -> Promise<Void> {
        Logger.info("")

        return Promise<Void>()
    }

    public func syncAllContactsIfFullSyncRequested() -> Promise<Void> {
        Logger.info("")

        return Promise<Void>()
    }
}

#endif
