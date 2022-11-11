//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSGroupThread {
    func updateWithStorySendEnabled(
        _ storySendEnabled: Bool,
        transaction: SDSAnyWriteTransaction,
        updateStorageService: Bool = true
    ) {
        let wasStorySendEnabled = self.isStorySendExplicitlyEnabled
        updateWithStoryViewMode(storySendEnabled ? .explicit : .disabled, transaction: transaction)

        if updateStorageService {
            storageServiceManager.recordPendingUpdates(groupModel: groupModel)
        }

        if !wasStorySendEnabled, storySendEnabled {
            // When enabling after being disabled, always unhide the story context.
            if
                let storyContextAssociatedData = StoryFinder.associatedData(for: self, transaction: transaction),
                storyContextAssociatedData.isHidden
            {
                storyContextAssociatedData.update(
                    updateStorageService: updateStorageService,
                    isHidden: false,
                    transaction: transaction
                )
            }
        }
    }

    var isStorySendExplicitlyEnabled: Bool {
        storyViewMode == .explicit
    }

    func isStorySendEnabled(transaction: SDSAnyReadTransaction) -> Bool {
        if isStorySendExplicitlyEnabled { return true }
        return StoryFinder.latestStoryForThread(self, transaction: transaction) != nil
    }
}

public extension TSThreadStoryViewMode {
    var storageServiceMode: StorageServiceProtoGroupV2RecordStorySendMode {
        switch self {
        case .default:
            return .default
        case .explicit:
            return .enabled
        case .disabled:
            return .disabled
        case .blockList:
            owsFailDebug("Unexpected story mode")
            return .default
        }
    }

    init(storageServiceMode: StorageServiceProtoGroupV2RecordStorySendMode) {
        switch storageServiceMode {
        case .default:
            self = .default
        case .disabled:
            self = .disabled
        case .enabled:
            self = .explicit
        case .UNRECOGNIZED(let value):
            owsFailDebug("Unexpected story mode \(value)")
            self = .default
        }
    }
}
