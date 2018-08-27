//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

enum ExperienceUpgradeId: String {
    case videoCalling = "001",
    callKit = "002",
    introducingProfiles = "003",
    introducingReadReceipts = "004",
    introducingCustomNotificationAudio = "005"
}

@objc public class ExperienceUpgradeFinder: NSObject {

    // MARK: - Singleton class

    @objc(sharedManager)
    public static let shared = ExperienceUpgradeFinder()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

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
                                 image: #imageLiteral(resourceName: "introductory_splash_profile"))
    }

    var introducingReadReceipts: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingReadReceipts.rawValue,
                                 title: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_READ_RECEIPTS_TITLE", comment: "Header for upgrade experience"),
                                 body: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_READ_RECEIPTS_DESCRIPTION", comment: "Description of new profile feature for upgrading (existing) users"),
                                 image: #imageLiteral(resourceName: "introductory_splash_read_receipts"))
    }

    var configurableNotificationAudio: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingCustomNotificationAudio.rawValue,
                                 title: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_NOTIFICATION_AUDIO_TITLE", comment: "Header for upgrade experience"),
                                 body: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_NOTIFICATION_AUDIO_DESCRIPTION", comment: "Description for notification audio customization"),
                                 image: #imageLiteral(resourceName: "introductory_splash_custom_audio"))
    }

    // Keep these ordered by increasing uniqueId.
    @objc
    public var allExperienceUpgrades: [ExperienceUpgrade] {
        return [
            // Disable old experience upgrades. Most people have seen them by now, and accomodating multiple makes layout harder.
            // Note if we ever want to show multiple experience upgrades again
            // we'll have to update the layout in ExperienceUpgradesPageViewController
            //
            // videoCalling,
            // (UIDevice.current.supportsCallKit ? callKit : nil),
            // introducingProfiles,
            // introducingReadReceipts,
            configurableNotificationAudio
        ].compactMap { $0 }
    }

    // MARK: - Instance Methods

    @objc public func allUnseen(transaction: YapDatabaseReadTransaction) -> [ExperienceUpgrade] {
        return allExperienceUpgrades.filter { ExperienceUpgrade.fetch(uniqueId: $0.uniqueId!, transaction: transaction) == nil }
    }

    @objc public func markAllAsSeen(transaction: YapDatabaseReadWriteTransaction) {
        Logger.info("marking experience upgrades as seen")
        allExperienceUpgrades.forEach { $0.save(with: transaction) }
    }
}
