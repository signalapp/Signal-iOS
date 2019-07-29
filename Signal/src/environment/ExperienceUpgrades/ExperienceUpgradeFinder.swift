//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

enum ExperienceUpgradeId: String {
    case introducingStickers = "008"
}

@objc public class ExperienceUpgradeFinder: NSObject {

    // MARK: - Singleton class

    @objc(sharedManager)
    public static let shared = ExperienceUpgradeFinder()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    var stickers: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingStickers.rawValue)
    }

    // Keep these ordered by increasing uniqueId.
    @objc
    public var allExperienceUpgrades: [ExperienceUpgrade] {
        guard FeatureFlags.stickerSend else {
            return []
        }
        return [
            stickers
        ].compactMap { $0 }
    }

    // MARK: - Instance Methods

    @objc
    public func allUnseen(transaction: SDSAnyReadTransaction) -> [ExperienceUpgrade] {
        let seen = ExperienceUpgrade.anyFetchAll(transaction: transaction)
        let seenIds = seen.map { $0.uniqueId! }
        return allExperienceUpgrades.filter { !seenIds.contains($0.uniqueId!) }
    }

    @objc
    public func markAsSeen(experienceUpgrade: ExperienceUpgrade, transaction: SDSAnyWriteTransaction) {
        Logger.info("marking experience upgrade as seen")
        experienceUpgrade.anyInsert(transaction: transaction)
    }

    @objc
    public func markAllAsSeen(transaction: SDSAnyWriteTransaction) {
        Logger.info("marking experience upgrades as seen")
        let unseen = allUnseen(transaction: transaction)
        unseen.forEach { $0.anyInsert(transaction: transaction) }
    }
}
