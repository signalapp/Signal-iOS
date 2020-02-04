//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Reachability

public enum ExperienceUpgradeId: String, CaseIterable {
    case introducingPins = "009"
    case reactions = "010"
    case profileNameReminder = "011"
    case messageRequests = "012"

    // Until this flag is true the upgrade won't display to users.
    var hasLaunched: Bool {
        switch self {
        case .introducingPins:
            // The PIN setup flow requires an internet connection
            return RemoteConfig.pinsForEveryone &&
                SSKEnvironment.shared.reachabilityManager.isReachable
        case .reactions:
            return FeatureFlags.reactionSend
        case .profileNameReminder:
            return RemoteConfig.profileNameReminder
        case .messageRequests:
            return FeatureFlags.messageRequest
        }
    }

    // Some upgrades stop running after a certain date. This lets
    // us know if we're still before that end date.
    var hasExpired: Bool {
        let expirationDate: TimeInterval

        switch self {
        case .reactions:
            // March 5, 2020 @ 12am UTC
            expirationDate = 1583366400
        default:
            expirationDate = Date.distantFuture.timeIntervalSince1970
        }

        return Date().timeIntervalSince1970 > expirationDate
    }

    // If false, this will be marked complete after registration
    // without ever presenting to the user.
    var showNewUsers: Bool { false }
}

@objc
public class ExperienceUpgradeFinder: NSObject {

    // MARK: -

    public class func next(transaction: GRDBReadTransaction) -> ExperienceUpgrade? {
        return allActiveExperienceUpgrades(transaction: transaction).first { !$0.isSnoozed }
    }

    public class func allIncomplete(transaction: GRDBReadTransaction) -> [ExperienceUpgrade] {
        return allActiveExperienceUpgrades(transaction: transaction).filter { !$0.isComplete }
    }

    public class func hasIncomplete(experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBReadTransaction) -> Bool {
        return allIncomplete(transaction: transaction).contains { experienceUpgradeId.rawValue == $0.uniqueId }
    }

    public class func markAsViewed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as seen \(experienceUpgrade.uniqueId)")
        experienceUpgrade.upsertWith(transaction: transaction.asAnyWrite) { experienceUpgrade in
            // Only mark as viewed if it has yet to be viewed.
            guard experienceUpgrade.firstViewedTimestamp == 0 else { return }
            experienceUpgrade.firstViewedTimestamp = Date().timeIntervalSince1970
        }
    }

    public class func markAsSnoozed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as snoozed \(experienceUpgrade.uniqueId)")
        experienceUpgrade.upsertWith(transaction: transaction.asAnyWrite) { $0.lastSnoozedTimestamp = Date().timeIntervalSince1970 }
    }

    public class func markAsComplete(experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as complete \(experienceUpgradeId)")
        allActiveExperienceUpgrades(transaction: transaction)
            .filter { $0.id == experienceUpgradeId }
            .forEach { markAsComplete(experienceUpgrade: $0, transaction: transaction) }
    }

    public class func markAsComplete(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as complete \(experienceUpgrade.uniqueId)")
        experienceUpgrade.upsertWith(transaction: transaction.asAnyWrite) { $0.isComplete = true }
    }

    @objc
    public class func markAllCompleteForNewUser(transaction: GRDBWriteTransaction) {
        allActiveExperienceUpgrades(transaction: transaction)
            .lazy
            .filter { !$0.id.showNewUsers }
            .forEach { markAsComplete(experienceUpgrade: $0, transaction: transaction) }
    }

    // MARK: - Experience Specific Helpers

    @objc
    public class func hasPendingPinExperienceUpgrade(transaction: GRDBReadTransaction) -> Bool {
        return hasIncomplete(experienceUpgradeId: .introducingPins, transaction: transaction)
    }

    @objc
    class func clearProfileNameReminder(transaction: GRDBWriteTransaction) {
        ExperienceUpgradeFinder.markAsComplete(experienceUpgradeId: .profileNameReminder, transaction: transaction)
    }

    // MARK: -

    /// Returns an array of all experience upgrades currently being run that have
    /// yet to be completed. Sorted by the order of the `ExperienceUpgradeId` enumeration.
    private class func allActiveExperienceUpgrades(transaction: GRDBReadTransaction) -> [ExperienceUpgrade] {
        // Only the primary device will ever see experience upgrades.
        // TODO: We may eventually sync these and show them on linked devices.
        guard SSKEnvironment.shared.tsAccountManager.isRegisteredPrimaryDevice else { return [] }

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
            if !experienceUpgrade.isComplete { experienceUpgrades.append(experienceUpgrade) }
            unsavedIds.removeAll { $0 == experienceUpgrade.uniqueId }
        }

        for id in unsavedIds {
            experienceUpgrades.append(ExperienceUpgrade(uniqueId: id))
        }

        return experienceUpgrades.sorted { lhs, rhs in
            guard let lhsIndex = activeIds.firstIndex(of: lhs.uniqueId),
                let rhsIndex = activeIds.firstIndex(of: rhs.uniqueId) else {
                owsFailDebug("failed to find index for uniqueIds \(lhs.uniqueId) \(rhs.uniqueId)")
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
}

public extension ExperienceUpgrade {
    var id: ExperienceUpgradeId! {
        return ExperienceUpgradeId(rawValue: uniqueId)
    }

    var isSnoozed: Bool {
        guard lastSnoozedTimestamp > 0 else { return false }
        // If it hasn't been two days since we were snoozed, wait to show again.
        return -Date(timeIntervalSince1970: lastSnoozedTimestamp).timeIntervalSinceNow <= kDayInterval * 2
    }

    var daysSinceFirstViewed: Int {
        guard firstViewedTimestamp > 0 else { return 0 }
        let secondsSinceFirstView = -Date(timeIntervalSince1970: firstViewedTimestamp).timeIntervalSinceNow
        return Int(secondsSinceFirstView / kDayInterval)
    }

    var hasViewed: Bool { firstViewedTimestamp > 0 }

    func upsertWith(transaction: SDSAnyWriteTransaction, changeBlock: (ExperienceUpgrade) -> Void) {
        let experienceUpgrade = ExperienceUpgrade.anyFetch(uniqueId: uniqueId, transaction: transaction) ?? self
        changeBlock(experienceUpgrade)
        experienceUpgrade.anyUpsert(transaction: transaction)
    }
}
