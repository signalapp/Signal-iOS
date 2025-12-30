//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SyncManagerProtocol: SyncManagerProtocolObjc, SyncManagerProtocolSwift {}

// MARK: -

@objc
public protocol SyncManagerProtocolObjc {
    func sendConfigurationSyncMessage()
}

// MARK: -

public protocol SyncManagerProtocolSwift {
    func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: TimeInterval) -> Promise<[String]>

    func sendAllSyncRequestMessagesIfNecessary() -> Promise<Void>
    func sendAllSyncRequestMessages(timeout: TimeInterval) -> Promise<Void>

    func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: DBWriteTransaction)
    func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: DBWriteTransaction)

    func syncAllContacts() async throws
    func syncAllContactsIfFullSyncRequested() async throws

    func sendFetchLatestProfileSyncMessage(tx: DBWriteTransaction)
    func sendFetchLatestStorageManifestSyncMessage() async
    func sendFetchLatestSubscriptionStatusSyncMessage()

    func sendKeysSyncMessage()
    func sendKeysSyncMessage(tx: DBWriteTransaction)
    func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: DBWriteTransaction)
    func sendKeysSyncRequestMessage(transaction: DBWriteTransaction)

    func processIncomingFetchLatestSyncMessage(_ syncMessage: SSKProtoSyncMessageFetchLatest, transaction: DBWriteTransaction)
    func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: DBWriteTransaction,
    )
    func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType)
    func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType, transaction: DBWriteTransaction)
}
