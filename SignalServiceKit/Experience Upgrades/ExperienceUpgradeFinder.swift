//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Contacts

public enum ExperienceUpgradeId: String, CaseIterable, Dependencies {
    // Experience upgrades are prioritized based on their order in this
    // enum, so the first entries in the enum (introducing pins) will
    // show before later entris in the enum (pin reminder) when multiple
    // upgrades are eligible for presentation.
    case introducingPins = "009"
    case notificationPermissionReminder
    case subscriptionMegaphone
    case pinReminder // Never saved, used to periodically prompt the user for their PIN
    case contactPermissionReminder

    // Until this flag is true the upgrade won't display to users.
    func hasLaunched(transaction: GRDBReadTransaction) -> Bool {
        AssertIsOnMainThread()

        if let registrationDate = tsAccountManager.registrationDate(with: transaction.asAnyRead) {
            guard Date().timeIntervalSince(registrationDate) >= delayAfterRegistration else {
                return false
            }
        }

        switch self {
        case .introducingPins:
            // The PIN setup flow requires an internet connection and you to not already have a PIN
            return RemoteConfig.kbs &&
                Self.reachabilityManager.isReachable &&
                !KeyBackupService.hasMasterKey(transaction: transaction.asAnyRead)
        case .pinReminder:
            return OWS2FAManager.shared.isDueForV2Reminder(transaction: transaction.asAnyRead)
        case .notificationPermissionReminder:
            let (promise, future) = Promise<Bool>.pending()

            Logger.info("Checking notification authorization")

            DispatchQueue.global(qos: .userInitiated).async {
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    Logger.info("Checked notification authorization \(settings.authorizationStatus)")
                    future.resolve(settings.authorizationStatus == .authorized)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                guard promise.result == nil else { return }
                future.reject(OWSGenericError("timeout fetching notification permissions"))
            }

            do {
                return !(try promise.wait())
            } catch {
                Logger.warn("failed to query notification permission")
                return false
            }
        case .contactPermissionReminder:
            return CNContactStore.authorizationStatus(for: CNEntityType.contacts) != .authorized
        case .subscriptionMegaphone:
            // Show the subscription megaphone IFF:
            // - It's remotely enabled
            // - The user has no / an expired subscription
            // - Their last subscription has been expired for more than 2 weeks
            return RemoteConfig.subscriptionMegaphone && (subscriptionManager.timeSinceLastSubscriptionExpiration(transaction: transaction.asAnyRead) > (2 * kWeekInterval))
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
             .subscriptionMegaphone:
            return false
        default:
            return true
        }
    }

    // This much time must have passed since the user registered
    // before the megaphone is ever presented.
    var delayAfterRegistration: TimeInterval {
        switch self {
        case .contactPermissionReminder,
             .notificationPermissionReminder:
            return kDayInterval
        case .introducingPins:
            // Create a PIN after KBS network failure
            return 2 * kHourInterval
        case .pinReminder:
            return 8 * kHourInterval
        case .subscriptionMegaphone:
            return 5 * kDayInterval
        }
    }

    // Some experience flows are dynamic and can be experience multiple
    // times so they don't need be saved to the database.
    var shouldSave: Bool {
        switch self {
        case .pinReminder:
            return false
        case .introducingPins:
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
        case .introducingPins:
            return false
        case .notificationPermissionReminder:
            return false
        case .contactPermissionReminder:
            return false
        case .subscriptionMegaphone:
            return false
        }
    }

    var snoozeDuration: TimeInterval {
        switch self {
        case .notificationPermissionReminder:
            return kDayInterval * 3
        case .contactPermissionReminder:
            return kDayInterval * 30
        case .subscriptionMegaphone:
            return RemoteConfig.subscriptionMegaphoneSnoozeInterval
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
        case .subscriptionMegaphone:
            return true
        default:
            return false
        }
    }
}

@objc
public class ExperienceUpgradeFinder: NSObject {

    // MARK: -

    public class func next(transaction: GRDBReadTransaction) -> ExperienceUpgrade? {
        return allActiveExperienceUpgrades(transaction: transaction).first { !$0.isSnoozed }
    }

    public class func markAsViewed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as seen \(experienceUpgrade.uniqueId)")
        experienceUpgrade.markAsViewed(transaction: transaction.asAnyWrite)
    }

    public class func markAsSnoozed(experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBWriteTransaction) {
        markAsSnoozed(experienceUpgrade: ExperienceUpgrade(uniqueId: experienceUpgradeId.rawValue), transaction: transaction)
    }

    public class func markAsSnoozed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as snoozed \(experienceUpgrade.uniqueId)")

        experienceUpgrade.markAsSnoozed(transaction: transaction.asAnyWrite)
    }

    public class func markAsComplete(experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBWriteTransaction) {
        markAsComplete(experienceUpgrade: ExperienceUpgrade(uniqueId: experienceUpgradeId.rawValue), transaction: transaction)
    }

    public class func markAsComplete(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        guard experienceUpgrade.experienceId.canBeCompleted else {
            return Logger.info("skipping marking experience upgrade as complete for experience upgrade \(experienceUpgrade.uniqueId)")
        }

        Logger.info("marking experience upgrade as complete \(experienceUpgrade.uniqueId)")

        experienceUpgrade.markAsComplete(transaction: transaction.asAnyWrite)
    }

    @objc
    public class func markAllCompleteForNewUser(transaction: GRDBWriteTransaction) {
        ExperienceUpgradeId.allCases
            .filter { $0.skipForNewUsers }
            .forEach { markAsComplete(experienceUpgradeId: $0, transaction: transaction) }
    }

    // MARK: -

    /// Returns an array of all experience upgrades currently being run that have
    /// yet to be completed. Priority is determined by the order of
    /// the `ExperienceUpgradeId` enumeration
    private class func allActiveExperienceUpgrades(transaction: GRDBReadTransaction) -> [ExperienceUpgrade] {
        let isPrimaryDevice = Self.tsAccountManager.isRegisteredPrimaryDevice

        let activeIds = ExperienceUpgradeId
            .allCases
            .filter { $0.hasLaunched(transaction: transaction) && !$0.hasExpired && ($0.showOnLinkedDevices || isPrimaryDevice) }
            .map { $0.rawValue }

        var experienceUpgrades = [ExperienceUpgrade]()
        var unsavedIds = activeIds

        // Query all saved experience upgrades...
        ExperienceUpgrade.anyEnumerate(transaction: transaction.asAnyRead) { experienceUpgrade, _ in
            guard activeIds.contains(experienceUpgrade.uniqueId) else {
                // Only load active upgrades.
                return
            }

            guard experienceUpgrade.experienceId.shouldSave else {
                // Ignore saved upgrades that we don't currently save.
                return
            }

            if !experienceUpgrade.isComplete {
                experienceUpgrades.append(experienceUpgrade)
            }

            unsavedIds.removeAll { $0 == experienceUpgrade.uniqueId }
        }

        // ...and instantiate new ones for any not-saved ones.
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
    var experienceId: ExperienceUpgradeId! {
        return ExperienceUpgradeId(rawValue: uniqueId)
    }

    var isSnoozed: Bool {
        guard lastSnoozedTimestamp > 0 else { return false }
        // If it hasn't been two days since we were snoozed, wait to show again.
        return -Date(timeIntervalSince1970: lastSnoozedTimestamp).timeIntervalSinceNow <= experienceId.snoozeDuration
    }

    var daysSinceFirstViewed: Int {
        guard firstViewedTimestamp > 0 else { return 0 }
        let secondsSinceFirstView = -Date(timeIntervalSince1970: firstViewedTimestamp).timeIntervalSinceNow
        return Int(secondsSinceFirstView / kDayInterval)
    }
}
