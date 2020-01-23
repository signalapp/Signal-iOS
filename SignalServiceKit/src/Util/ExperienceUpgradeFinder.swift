//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Reachability

public enum ExperienceUpgradeId: String, CaseIterable {
    case introducingStickers = "008"
    case introducingPins = "009"

    var hasLaunched: Bool {
        switch self {
        case .introducingStickers:
            return FeatureFlags.stickerSend
        case .introducingPins:
            // The PIN setup flow requires an internet connection
            // and should only be run on the primary device.
            return FeatureFlags.pinsForEveryone &&
                TSAccountManager.sharedInstance().isRegisteredPrimaryDevice &&
                SSKEnvironment.shared.reachabilityManager.isReachable
        }
    }

    // Some upgrades stop running after a certain date. This lets
    // us know if we're still before that end date.
    var hasExpired: Bool {
        var expirationTimestamp: TimeInterval?
        switch self {
        case .introducingStickers:
            // January 20, 2020 @ 12am UTC
            expirationTimestamp = 1579478400
        default:
            break
        }

        if let expirationTimestamp = expirationTimestamp {
            return expirationTimestamp < Date().timeIntervalSince1970
        }

        return false
    }
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
    public var pins: ExperienceUpgrade {
        return ExperienceUpgrade(uniqueId: ExperienceUpgradeId.introducingPins.rawValue)
    }

    // MARK: - Instance Methods

    @objc
    public func next(transaction: GRDBReadTransaction) -> ExperienceUpgrade? {
        return allActiveExperienceUpgrades(transaction: transaction).first { !$0.isSnoozed }
    }

    @objc
    public func allUnviewed(transaction: GRDBReadTransaction) -> [ExperienceUpgrade] {
        return allActiveExperienceUpgrades(transaction: transaction).filter { $0.hasViewed }
    }

    public func hasUnviewed(experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBReadTransaction) -> Bool {
        return allUnviewed(transaction: transaction).contains { experienceUpgradeId.rawValue == $0.uniqueId }
    }

    @objc
    public func markAsViewed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as seen \(experienceUpgrade.uniqueId)")
        experienceUpgrade.firstViewedTimestamp = Date().timeIntervalSince1970
        experienceUpgrade.anyUpsert(transaction: transaction.asAnyWrite)
    }

    @objc
    public func markAsSnoozed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as snoozed \(experienceUpgrade.uniqueId)")
        experienceUpgrade.lastSnoozedTimestamp = Date().timeIntervalSince1970
        experienceUpgrade.anyUpsert(transaction: transaction.asAnyWrite)
    }

    @objc
    public func markAsComplete(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as complete \(experienceUpgrade.uniqueId)")
        experienceUpgrade.isComplete = true
        experienceUpgrade.anyUpsert(transaction: transaction.asAnyWrite)
    }

    @objc
    public func markAllComplete(transaction: GRDBWriteTransaction) {
        allActiveExperienceUpgrades(transaction: transaction).forEach { markAsComplete(experienceUpgrade: $0, transaction: transaction) }
    }

    @objc
    public func hasPendingPinExperienceUpgrade(transaction: GRDBReadTransaction) -> Bool {
        return hasUnviewed(experienceUpgradeId: .introducingPins, transaction: transaction)
    }

    /// Returns an array of all experience upgrades currently being run that have
    /// yet to be completed. Sorted by the order of the `ExperienceUpgradeId` enumeration.
    private func allActiveExperienceUpgrades(transaction: GRDBReadTransaction) -> [ExperienceUpgrade] {
        let activeIds = ExperienceUpgradeId.allCases.filter { $0.hasLaunched && !$0.hasExpired }.map { $0.rawValue }

        // We don't include `isComplete` in the query as we want to initialize
        // new records for any active ids that haven't had one recorded yet.
        let cursor = ExperienceUpgrade.grdbFetchCursor(
            sql: """
                SELECT * FROM \(ExperienceUpgradeRecord.databaseTableName)
                WHERE \(experienceUpgradeColumn: .uniqueId) IN (\(activeIds.map { "\'\($0)'" }.joined(separator: ",")))
            """,
            transaction: transaction
        )

        var experienceUpgrades = [ExperienceUpgrade]()
        var unsavedIds = activeIds

        while true {
            guard let experienceUpgrade = try? cursor.next() else { break }
            experienceUpgrades.append(experienceUpgrade)
            unsavedIds.removeAll { $0 == experienceUpgrade.uniqueId }
        }

        for id in unsavedIds {
            experienceUpgrades.append(ExperienceUpgrade(uniqueId: id))
        }

        return experienceUpgrades.filter { !$0.isComplete }.sorted { lhs, rhs in
            guard let lhsIndex = activeIds.firstIndex(of: lhs.uniqueId),
                let rhsIndex = activeIds.firstIndex(of: rhs.uniqueId) else {
                owsFailDebug("failed to find index for uniqueIds \(lhs.uniqueId) \(rhs.uniqueId)")
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
}

@objc
public extension ExperienceUpgrade {
    var isSnoozed: Bool {
        guard lastSnoozedTimestamp > 0 else { return false }
        // If it hasn't been two days since we were snoozed, wait to show again.
        return -Date(timeIntervalSince1970: lastSnoozedTimestamp).timeIntervalSinceNow <= kDayInterval * 2
    }

    var daysSinceFirstViewed: Int {
        guard firstViewedTimestamp > 0 else { return 0 }
        let secondsSinceFirstView = -Date(timeIntervalSince1970: lastSnoozedTimestamp).timeIntervalSinceNow
        return Int(secondsSinceFirstView / kDayInterval)
    }

    var hasViewed: Bool { firstViewedTimestamp > 0 }
}
