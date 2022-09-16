//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSGroupThread {
    func updateWithStorySendEnabled(_ storySendEnabled: Bool, shouldUpdateStorageService: Bool = true, transaction: SDSAnyWriteTransaction) {
        updateWithStoryViewMode(storySendEnabled ? .explicit : .none, transaction: transaction)

        if shouldUpdateStorageService {
            storageServiceManager.recordPendingUpdates(groupModel: groupModel)
        }
    }

    var isStorySendEnabled: Bool {
        storyViewMode == .explicit
    }
}
