//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

enum ExperienceUpgradeId: String {
    case videoCalling = "001",
    callKit = "002"
}

class ExperienceUpgradeFinder: NSObject {
    public let TAG = "[ExperienceUpgradeFinder]"

    // Keep these ordered by increasing uniqueId.
    private var allExperienceUpgrades: [ExperienceUpgrade] {
        var upgrades = [ExperienceUpgrade(uniqueId: ExperienceUpgradeId.videoCalling.rawValue,
                                          title: NSLocalizedString("UPGRADE_EXPERIENCE_VIDEO_TITLE", comment: "Header for upgrade experience"),
                                          body: NSLocalizedString("UPGRADE_EXPERIENCE_VIDEO_DESCRIPTION", comment: "Description of video calling to upgrading (existing) users"),
                                          image: #imageLiteral(resourceName: "introductory_splash_video_calling"))]

        if UIDevice.current.supportsCallKit {
            upgrades.append(ExperienceUpgrade(uniqueId: ExperienceUpgradeId.callKit.rawValue,
                                              title: NSLocalizedString("UPGRADE_EXPERIENCE_CALLKIT_TITLE", comment: "Header for upgrade experience"),
                                              body: NSLocalizedString("UPGRADE_EXPERIENCE_CALLKIT_DESCRIPTION", comment: "Description of CallKit to upgrading (existing) users"),
                                              image: #imageLiteral(resourceName: "introductory_splash_callkit")))
        }

        return upgrades
    }

    // MARK: - Instance Methods

    public func allUnseen(transaction: YapDatabaseReadTransaction) -> [ExperienceUpgrade] {
        return allExperienceUpgrades.filter { ExperienceUpgrade.fetch(uniqueId: $0.uniqueId, transaction: transaction) == nil }
    }

    public func markAllAsSeen(transaction: YapDatabaseReadWriteTransaction) {
        Logger.info("\(TAG) marking experience upgrades as seen")
        allExperienceUpgrades.forEach { $0.save(with: transaction) }
    }
}
