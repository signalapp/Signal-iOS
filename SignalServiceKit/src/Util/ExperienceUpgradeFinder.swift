//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import Contacts

public enum ExperienceUpgradeId: String, CaseIterable {
    case introducingPins = "009"
    case pinReminder // Never saved, used to periodically prompt the user for their PIN
    case notificationPermissionReminder
    case contactPermissionReminder
    case linkPreviews
    case researchMegaphone1
    case groupsV2AndMentionsSplash2
    case groupCallsMegaphone

    // Until this flag is true the upgrade won't display to users.
    func hasLaunched(transaction: GRDBReadTransaction) -> Bool {
        AssertIsOnMainThread()

        switch self {
        case .introducingPins:
            // The PIN setup flow requires an internet connection and you to not already have a PIN
            return RemoteConfig.kbs &&
                SSKEnvironment.shared.reachabilityManager.isReachable &&
                !KeyBackupService.hasMasterKey(transaction: transaction.asAnyRead)
        case .pinReminder:
            return OWS2FAManager.shared().isDueForV2Reminder(transaction: transaction.asAnyRead)
        case .notificationPermissionReminder:
            let (promise, resolver) = Promise<Bool>.pending()

            Logger.info("Checking notification authorization")

            DispatchQueue.global(qos: .userInitiated).async {
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    Logger.info("Checked notification authorization \(settings.authorizationStatus)")
                    resolver.fulfill(settings.authorizationStatus == .authorized)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                guard promise.result == nil else { return }
                resolver.reject(OWSGenericError("timeout fetching notification permissions"))
            }

            do {
                return !(try promise.wait())
            } catch {
                owsFailDebug("failed to query notification permission")
                return false
            }
        case .contactPermissionReminder:
            return CNContactStore.authorizationStatus(for: CNEntityType.contacts) != .authorized
        case .linkPreviews:
            return true
        case .researchMegaphone1:
            return RemoteConfig.researchMegaphone
        case .groupsV2AndMentionsSplash2:
            return FeatureFlags.groupsV2showSplash
        case .groupCallsMegaphone:
            return RemoteConfig.groupCalling
        }
    }

    // Some upgrades stop running after a certain date. This lets
    // us know if we're still before that end date.
    var hasExpired: Bool {
        let expirationDate: TimeInterval

        switch self {
        default:
            expirationDate = Date.distantFuture.timeIntervalSince1970
        }

        return Date().timeIntervalSince1970 > expirationDate
    }

    // If false, this will not be marked complete after registration.
    var skipForNewUsers: Bool {
        switch self {
        case .introducingPins,
             .researchMegaphone1:
            return false
        default:
            return true
        }
    }

    // In addition to being sorted by their order as defined in this enum,
    // experience upgrades are also sorted by priority. For example, a high
    // priority upgrade will always show before a low priority experience
    // upgrade, even if it shows up later in the list.
    enum Priority: Int {
        case low
        case medium
        case high
    }
    var priority: Priority {
        switch self {
        case .introducingPins:
            return .high
        case .linkPreviews:
            return .medium
        case .pinReminder:
            return .medium
        case .notificationPermissionReminder:
            return .medium
        case .contactPermissionReminder:
            return .medium
        case .researchMegaphone1:
            return .low
        case .groupsV2AndMentionsSplash2:
            return .medium
        case .groupCallsMegaphone:
            return .medium
        }
    }

    // Some experience flows are dynamic and can be experience multiple
    // times so they don't need be saved to the database.
    var shouldSave: Bool {
        switch self {
        case .pinReminder:
            return false
        default:
            return true
        }
    }

    // Some experience upgrades are dynamic, but still track state (like
    // snooze duration), but can never be permanently completed.
    var canBeCompleted: Bool {
        switch self {
        case .pinReminder:
            return false
        case .notificationPermissionReminder:
            return false
        case .contactPermissionReminder:
            return false
        default:
            return true
        }
    }

    var snoozeDuration: TimeInterval {
        switch self {
        case .notificationPermissionReminder:
            return kDayInterval * 30
        case .contactPermissionReminder:
            return kDayInterval * 30
        default:
            return kDayInterval * 2
        }
    }

    var showOnLinkedDevices: Bool {
        switch self {
        case .notificationPermissionReminder:
            return true
        case .contactPermissionReminder:
            return true
        default:
            return false
        }
    }

    var objcRepresentation: ObjcExperienceUpgradeId {
        switch self {
        case .introducingPins:                  return .introducingPins
        case .pinReminder:                      return .pinReminder
        case .notificationPermissionReminder:   return .notificationPermissionReminder
        case .contactPermissionReminder:        return .contactPermissionReminder
        case .linkPreviews:                     return .linkPreviews
        case .researchMegaphone1:               return .researchMegaphone1
        case .groupsV2AndMentionsSplash2:       return .groupsV2AndMentionsSplash2
        case .groupCallsMegaphone:              return .groupCallsMegaphone
        }
    }
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
        markAsComplete(experienceUpgrade: ExperienceUpgrade(uniqueId: experienceUpgradeId.rawValue), transaction: transaction)
    }

    public class func markAsComplete(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        guard experienceUpgrade.id.canBeCompleted else {
            return Logger.info("skipping marking experience upgrade as complete for experience upgrade \(experienceUpgrade.uniqueId)")
        }

        Logger.info("marking experience upgrade as complete \(experienceUpgrade.uniqueId)")

        experienceUpgrade.upsertWith(transaction: transaction.asAnyWrite) { $0.isComplete = true }
    }

    @objc
    public class func markAllCompleteForNewUser(transaction: GRDBWriteTransaction) {
        ExperienceUpgradeId.allCases
            .filter { $0.skipForNewUsers }
            .forEach { markAsComplete(experienceUpgradeId: $0, transaction: transaction) }
    }

    // MARK: -

    /// Returns an array of all experience upgrades currently being run that have
    /// yet to be completed. Sorted by priority from highest to lowest. For equal
    /// priority upgrades follows the order of the `ExperienceUpgradeId` enumeration
    private class func allActiveExperienceUpgrades(transaction: GRDBReadTransaction) -> [ExperienceUpgrade] {
        let isPrimaryDevice = SSKEnvironment.shared.tsAccountManager.isRegisteredPrimaryDevice

        let activeIds = ExperienceUpgradeId
            .allCases
            .filter { $0.hasLaunched(transaction: transaction) && !$0.hasExpired && ($0.showOnLinkedDevices || isPrimaryDevice) }
            .map { $0.rawValue }

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
            guard experienceUpgrade.id.shouldSave else {
                // Ignore saved upgrades that we don't currently save.
                continue
            }
            if !experienceUpgrade.isComplete && !experienceUpgrade.hasCompletedVisibleDuration {
                experienceUpgrades.append(experienceUpgrade)
            }

            unsavedIds.removeAll { $0 == experienceUpgrade.uniqueId }
        }

        for id in unsavedIds {
            experienceUpgrades.append(ExperienceUpgrade(uniqueId: id))
        }

        return experienceUpgrades.sorted { lhs, rhs in
            guard lhs.id.priority == rhs.id.priority else {
                return lhs.id.priority.rawValue > rhs.id.priority.rawValue
            }

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
        return -Date(timeIntervalSince1970: lastSnoozedTimestamp).timeIntervalSinceNow <= id.snoozeDuration
    }

    var daysSinceFirstViewed: Int {
        guard firstViewedTimestamp > 0 else { return 0 }
        let secondsSinceFirstView = -Date(timeIntervalSince1970: firstViewedTimestamp).timeIntervalSinceNow
        return Int(secondsSinceFirstView / kDayInterval)
    }

    var hasCompletedVisibleDuration: Bool {
        switch id {
        case .researchMegaphone1: return daysSinceFirstViewed >= 7
        default: return false
        }
    }

    var hasViewed: Bool { firstViewedTimestamp > 0 }

    func upsertWith(transaction: SDSAnyWriteTransaction, changeBlock: (ExperienceUpgrade) -> Void) {
        guard id.shouldSave else { return Logger.debug("Skipping save for experience upgrade \(String(describing: id))") }

        let experienceUpgrade = ExperienceUpgrade.anyFetch(uniqueId: uniqueId, transaction: transaction) ?? self
        changeBlock(experienceUpgrade)
        experienceUpgrade.anyUpsert(transaction: transaction)
    }
}

/// A workaround bridge to allow PrivacySettingsTableViewController to clear an experience upgrade
/// Feel free to remove this if that ever gets migrated to Swift
@objc(OWSObjcExperienceUpgradeId)
public enum ObjcExperienceUpgradeId: Int {
    case introducingPins
    case pinReminder
    case notificationPermissionReminder
    case contactPermissionReminder
    case linkPreviews
    case researchMegaphone1
    case groupsV2AndMentionsSplash2
    case groupCallsMegaphone

    public var swiftRepresentation: ExperienceUpgradeId {
        switch self {
        case .introducingPins:                  return .introducingPins
        case .pinReminder:                      return .pinReminder
        case .notificationPermissionReminder:   return .notificationPermissionReminder
        case .contactPermissionReminder:        return .contactPermissionReminder
        case .linkPreviews:                     return .linkPreviews
        case .researchMegaphone1:               return .researchMegaphone1
        case .groupsV2AndMentionsSplash2:       return .groupsV2AndMentionsSplash2
        case .groupCallsMegaphone:              return .groupCallsMegaphone
        }
    }
}
