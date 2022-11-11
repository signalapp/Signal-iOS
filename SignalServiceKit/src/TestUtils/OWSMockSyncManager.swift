//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objc
public class OWSMockSyncManager: NSObject, SyncManagerProtocol {
    public typealias MockBlock = () -> Void

    @objc
    public var syncGroupsHook: MockBlock?

    @objc
    public func sendConfigurationSyncMessage() {
        Logger.info("")
    }

    @objc
    public func sendAllSyncRequestMessages() -> AnyPromise {
        Logger.info("")

        return AnyPromise(Promise.value(()))
    }

    @objc
    public func sendAllSyncRequestMessages(timeout: TimeInterval) -> AnyPromise {
        Logger.info("")

        return AnyPromise(Promise.value(()))
    }

    public func sendFetchLatestProfileSyncMessage() {
        Logger.info("")
    }

    public func sendFetchLatestStorageManifestSyncMessage() {
        Logger.info("")
    }

    public func sendFetchLatestSubscriptionStatusSyncMessage() {
        Logger.info("")
    }

    public func sendPniIdentitySyncRequestMessage() {
        Logger.info("")
    }

    public func sendKeysSyncMessage() {
        Logger.info("")
    }

    public func sendPniIdentitySyncMessage() {
        Logger.info("")
    }

    public func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingFetchLatestSyncMessage(_ syncMessage: SSKProtoSyncMessageFetchLatest, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingGroupsSyncMessage(_ syncMessage: SSKProtoSyncMessageGroups, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func sendKeysSyncRequestMessage(transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func processIncomingMessageRequestResponseSyncMessage(_ syncMessage: SSKProtoSyncMessageMessageRequestResponse, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType) {
        Logger.info("")
    }

    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
    }

    @objc
    public func syncLocalContact() -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc
    public func syncAllContacts() -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc
    public func syncGroups(transaction: SDSAnyWriteTransaction, completion: @escaping Completion) {
        Logger.info("")

        syncGroupsHook?()

        completion()
    }
}

#endif
