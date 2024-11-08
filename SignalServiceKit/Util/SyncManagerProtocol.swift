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

    func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: SDSAnyWriteTransaction)
    func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: SDSAnyWriteTransaction)

    func syncAllContacts() -> Promise<Void>
    func syncAllContactsIfFullSyncRequested() -> Promise<Void>

    func sendFetchLatestProfileSyncMessage(tx: SDSAnyWriteTransaction)
    func sendFetchLatestStorageManifestSyncMessage() async
    func sendFetchLatestSubscriptionStatusSyncMessage()

    func sendKeysSyncMessage()
    func sendKeysSyncMessage(tx: SDSAnyWriteTransaction)
    func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: SDSAnyWriteTransaction)
    func sendKeysSyncRequestMessage(transaction: SDSAnyWriteTransaction)

    func processIncomingFetchLatestSyncMessage(_ syncMessage: SSKProtoSyncMessageFetchLatest, transaction: SDSAnyWriteTransaction)
    func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: SDSAnyWriteTransaction
    )
    func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType)
    func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType, transaction: SDSAnyWriteTransaction)
}
