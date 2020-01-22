//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Reachability

public enum ExperienceUpgradeId: String {
    case introducingStickers = "008"
    case introducingPins = "009"
}

@objc public class ExperienceUpgradeFinder: NSObject {

    // MARK: - Singleton class

    @objc(sharedManager)
    public static let shared = ExperienceUpgradeFinder()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public var stickers: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingStickers.rawValue)
    }

    @objc
    public var pins: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingPins.rawValue)
    }

    // Keep these ordered by increasing uniqueId.
    @objc
    public var allExperienceUpgrades: [ExperienceUpgrade] {
        var upgrades = [ExperienceUpgrade]()

        if FeatureFlags.stickerSend {
            upgrades.append(stickers)
        }

        // The PIN setup flow requires an internet connection
        // and should only be run on the primary device.
        if FeatureFlags.pinsForEveryone,
            TSAccountManager.sharedInstance().isRegisteredPrimaryDevice,
            SSKEnvironment.shared.reachabilityManager.isReachable {
            upgrades.append(pins)
        }

        return upgrades
    }

    // MARK: - Instance Methods

    @objc
    public func allUnseen(transaction: SDSAnyReadTransaction) -> [ExperienceUpgrade] {
        let seen = ExperienceUpgrade.anyFetchAll(transaction: transaction)
        let seenIds = seen.map { $0.uniqueId }
        return allExperienceUpgrades.filter { !seenIds.contains($0.uniqueId) }
    }

    @objc
    public func hasUnseen(experienceUpgrade: ExperienceUpgrade, transaction: SDSAnyReadTransaction) -> Bool {
        return allUnseen(transaction: transaction).contains { experienceUpgrade.uniqueId == $0.uniqueId }
    }

    @objc
    public func markAsSeen(experienceUpgrade: ExperienceUpgrade, transaction: SDSAnyWriteTransaction) {
        Logger.info("marking experience upgrade as seen")
        experienceUpgrade.anyUpsert(transaction: transaction)
    }

    @objc
    public func markAllAsSeen(transaction: SDSAnyWriteTransaction) {
        Logger.info("marking experience upgrades as seen")
        let unseen = allUnseen(transaction: transaction)
        unseen.forEach { $0.anyInsert(transaction: transaction) }
    }
}
