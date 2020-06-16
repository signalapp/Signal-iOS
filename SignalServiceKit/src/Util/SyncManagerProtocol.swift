//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol SyncManagerProtocol: SyncManagerProtocolObjc, SyncManagerProtocolSwift {}

@objc
public protocol SyncManagerProtocolObjc {
    func sendConfigurationSyncMessage()

    func syncLocalContact() -> AnyPromise
    func syncAllContacts() -> AnyPromise
    func syncContacts(forSignalAccounts signalAccounts: [SignalAccount]) -> AnyPromise
    func syncGroups(transaction: SDSAnyWriteTransaction)

    func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: SDSAnyWriteTransaction)
    func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: SDSAnyWriteTransaction)
    func processIncomingGroupsSyncMessage(_ syncMessage: SSKProtoSyncMessageGroups, transaction: SDSAnyWriteTransaction)
    func processIncomingFetchLatestSyncMessage(_ syncMessage: SSKProtoSyncMessageFetchLatest, transaction: SDSAnyWriteTransaction)

    func sendFetchLatestProfileSyncMessage()
    func sendFetchLatestStorageManifestSyncMessage()
}

@objc
public protocol SyncManagerProtocolSwift {
    func sendKeysSyncMessage()

    func sendAllSyncRequestMessages() -> AnyPromise
    func sendAllSyncRequestMessages(timeout: TimeInterval) -> AnyPromise

    func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: SDSAnyWriteTransaction)
    func sendKeysSyncRequestMessage(transaction: SDSAnyWriteTransaction)

    func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: SDSAnyWriteTransaction
    )
    func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType)
    func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType, transaction: SDSAnyWriteTransaction)
}
