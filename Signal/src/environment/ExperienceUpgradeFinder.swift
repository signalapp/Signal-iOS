//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

enum ExperienceUpgradeId: String {
    case videoCalling = "001",
    callKit = "002",
    introducingProfiles = "003",
    introducingReadReceipts = "004"
}

class ExperienceUpgradeFinder: NSObject {
    public let TAG = "[ExperienceUpgradeFinder]"

    var videoCalling: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.videoCalling.rawValue,
                                 title: NSLocalizedString("UPGRADE_EXPERIENCE_VIDEO_TITLE", comment: "Header for upgrade experience"),
                                 body: NSLocalizedString("UPGRADE_EXPERIENCE_VIDEO_DESCRIPTION", comment: "Description of video calling to upgrading (existing) users"),
                                 image: #imageLiteral(resourceName: "introductory_splash_video_calling"))
    }

    var callKit: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.callKit.rawValue,
                                 title: NSLocalizedString("UPGRADE_EXPERIENCE_CALLKIT_TITLE", comment: "Header for upgrade experience"),
                                 body: NSLocalizedString("UPGRADE_EXPERIENCE_CALLKIT_DESCRIPTION", comment: "Description of CallKit to upgrading (existing) users"),
                                 image: #imageLiteral(resourceName: "introductory_splash_callkit"))
    }

    var introducingProfiles: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingProfiles.rawValue,
                                 title: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PROFILES_TITLE", comment: "Header for upgrade experience"),
                                 body: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PROFILES_DESCRIPTION", comment: "Description of new profile feature for upgrading (existing) users"),
                                 image:#imageLiteral(resourceName: "introductory_splash_profile"))
    }

    var introducingReadReceipts: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingReadReceipts.rawValue,
                                 title: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_READ_RECEIPTS_TITLE", comment: "Header for upgrade experience"),
                                 body: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_READ_RECEIPTS_DESCRIPTION", comment: "Description of new profile feature for upgrading (existing) users"),
                                 image:#imageLiteral(resourceName: "introductory_splash_read_receipts"))
    }

    // Keep these ordered by increasing uniqueId.
    private var allExperienceUpgrades: [ExperienceUpgrade] {
        return [
            // Disable old experience upgrades. Most people have seen them by now, and accomodating multiple makes layout harder.
            // Note if we ever want to show multiple experience upgrades again
            // we'll have to update the layout in ExperienceUpgradesPageViewController
            //
            // videoCalling,
            // (UIDevice.current.supportsCallKit ? callKit : nil),
            //  introducingProfiles,
            introducingReadReceipts
        ].flatMap { $0 }
    }

    // MARK: - Instance Methods

    public func allUnseen(transaction: YapDatabaseReadTransaction) -> [ExperienceUpgrade] {
        return allExperienceUpgrades.filter { ExperienceUpgrade.fetch(uniqueId: $0.uniqueId!, transaction: transaction) == nil }
    }

    public func markAllAsSeen(transaction: YapDatabaseReadWriteTransaction) {
        Logger.info("\(TAG) marking experience upgrades as seen")
        allExperienceUpgrades.forEach { $0.save(with: transaction) }
    }
}
