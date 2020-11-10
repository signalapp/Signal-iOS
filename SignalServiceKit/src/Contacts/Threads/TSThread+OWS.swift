//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSThread {

    var isGroupThread: Bool {
        return (self as? TSGroupThread) != nil
    }

    var isGroupV1Thread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return false
        }
        return groupThread.groupModel.groupsVersion == .V1
    }

    var isGroupV2Thread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return false
        }
        return groupThread.groupModel.groupsVersion == .V2
    }

    var groupModelIfGroupThread: TSGroupModel? {
        guard let groupThread = self as? TSGroupThread else {
            return nil
        }
        return groupThread.groupModel
    }

    var isBlockedByMigration: Bool {
        isGroupV1Thread && GroupManager.areMigrationsBlocking
    }

    var canSendToThread: Bool {
        !isBlockedByMigration
    }
}
