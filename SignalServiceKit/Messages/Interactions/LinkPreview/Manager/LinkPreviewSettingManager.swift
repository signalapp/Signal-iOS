//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol LinkPreviewSettingManager {
    func setAreLinkPreviewsEnabled(
        _ newValue: Bool,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    )
}

class LinkPreviewSettingManagerImpl: LinkPreviewSettingManager {
    private let linkPreviewSettingStore: LinkPreviewSettingStore
    private let storageServiceManager: any StorageServiceManager
    private let syncManager: any SyncManagerProtocol

    init(
        linkPreviewSettingStore: LinkPreviewSettingStore,
        storageServiceManager: any StorageServiceManager,
        syncManager: any SyncManagerProtocol
    ) {
        self.linkPreviewSettingStore = linkPreviewSettingStore
        self.storageServiceManager = storageServiceManager
        self.syncManager = syncManager
    }

    public func setAreLinkPreviewsEnabled(_ newValue: Bool, shouldSendSyncMessage: Bool, tx: any DBWriteTransaction) {
        self.linkPreviewSettingStore.setAreLinkPreviewsEnabled(newValue, tx: tx)

        if shouldSendSyncMessage {
            self.syncManager.sendConfigurationSyncMessage()
            self.storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }
}
