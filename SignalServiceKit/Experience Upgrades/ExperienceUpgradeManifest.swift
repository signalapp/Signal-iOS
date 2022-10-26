//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Contacts

public enum ExperienceUpgradeManifest: Dependencies {
    /// Prompts the user to create a PIN, if they did not create one during
    /// registration.
    ///
    /// Skipping a PIN is not user-selectable during registration, but is
    /// possible if KBS returned errors.
    case introducingPins

    /// Prompts the user to enable notifications permissions.
    case notificationPermissionReminder

    /// Prompts the user to donate :)
    case subscriptionMegaphone

    /// Prompts the user according to the contained ``RemoteMegaphoneModel``.
    ///
    /// Remote megaphones are fetched from the service, and expected to change
    /// over time.
    case remoteMegaphone(megaphone: RemoteMegaphoneModel)

    /// Prompts the user to enter their PIN, to help ensure they remember it.
    ///
    /// Note that this upgrade stores state in external components, rather than
    /// in an ``ExperienceUpgrade``.
    case pinReminder

    /// Prompts the user to enable contacts permissions.
    case contactPermissionReminder

    /// An unrecognized upgrade, which should generally be ignored/discarded.
    ///
    /// This may represent a persisted ``ExperienceUpgrade`` record which refers
    /// to an upgrade that has since been removed.
    case unrecognized(uniqueId: String)
}

// MARK: - Codable

extension ExperienceUpgradeManifest: Codable {

    public enum CodingKeys: String, CodingKey {
        /// Keys to the unique ID identifying a manifest.
        case uniqueId
        /// Keys to the remote megaphone for a manifest. Only present if the
        /// manifest represents a remote megaphone.
        case remoteMegaphone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let persistedUniqueId = try container.decode(String.self, forKey: .uniqueId)
        let persistedRemoteMegaphone = try container.decodeIfPresent(RemoteMegaphoneModel.self, forKey: .remoteMegaphone)

        self.init(uniqueId: persistedUniqueId, remoteMegaphone: persistedRemoteMegaphone)

        owsAssertDebug(uniqueId == persistedUniqueId, "Persisted unique ID does not match deserialized model!")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(uniqueId, forKey: .uniqueId)

        if case .remoteMegaphone(let megaphone) = self {
            try container.encode(megaphone, forKey: .remoteMegaphone)
        }
    }
}

// MARK: - From persisted unique IDs

extension ExperienceUpgradeManifest {
    /// Instantiate an ``ExperienceUpgradeManifest`` from the unique ID of a
    /// persisted ``ExperienceUpgrade`` which does not have a manifest.
    ///
    /// This is only relevant for ``ExperienceUpgrade``s that were persisted
    /// before the ``ExperienceUpgradeManifest`` was added.
    static func makeLegacy(fromPersistedExperienceUpgradeUniqueId uniqueId: String) -> ExperienceUpgradeManifest {
        ExperienceUpgradeManifest(uniqueId: uniqueId, remoteMegaphone: nil)
    }

    private init(uniqueId: String, remoteMegaphone: RemoteMegaphoneModel?) {
        self = {
            switch uniqueId {
            case Self.introducingPins.uniqueId:
                return .introducingPins
            case Self.notificationPermissionReminder.uniqueId:
                return .notificationPermissionReminder
            case Self.subscriptionMegaphone.uniqueId:
                return .subscriptionMegaphone
            case Self.pinReminder.uniqueId:
                return .pinReminder
            case Self.contactPermissionReminder.uniqueId:
                return .contactPermissionReminder
            default:
                break
            }

            if let megaphone = remoteMegaphone {
                return .remoteMegaphone(megaphone: megaphone)
            }

            return .unrecognized(uniqueId: uniqueId)
        }()
    }
}

// MARK: - Well-known, local manifests

extension ExperienceUpgradeManifest {
    /// Contains upgrade manifests that are well-known to the app.
    ///
    /// Examples of manifests _not_ listed here include upgrades that were once
    /// well-known, but have since been removed.
    static let wellKnownLocalUpgradeManifests: Set<ExperienceUpgradeManifest> = [
        .introducingPins,
        .notificationPermissionReminder,
        .subscriptionMegaphone,
        .pinReminder,
        .contactPermissionReminder
    ]
}

// MARK: - Unique IDs

extension ExperienceUpgradeManifest {
    /// The "unique ID" of this upgrade. Stable, and may be used for persistence.
    var uniqueId: String {
        switch self {
        case .introducingPins:
            // For historical compatibility, this experience has a unique ID
            // that does not match the enum case.
            return "009"
        case .notificationPermissionReminder:
            return "notificationPermissionReminder"
        case .subscriptionMegaphone:
            return "subscriptionMegaphone"
        case .remoteMegaphone(let megaphone):
            return megaphone.id
        case .pinReminder:
            return "pinReminder"
        case .contactPermissionReminder:
            return "contactPermissionReminder"
        case .unrecognized(let uniqueId):
            return uniqueId
        }
    }
}

extension ExperienceUpgradeManifest: Equatable {
    public static func == (lhs: ExperienceUpgradeManifest, rhs: ExperienceUpgradeManifest) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }
}

extension ExperienceUpgradeManifest: Hashable {
    public func hash(into hasher: inout Hasher) {
        uniqueId.hash(into: &hasher)
    }
}

// MARK: - Importance order

protocol ExperienceUpgradeSortable {
    /// The relative "importance" of this upgrade - i.e., whether this or
    /// another which of multiple upgrade should be preferred for presentation.
    ///
    /// Lower values indicate higher importance. When comparing, ties in the
    /// primary index are broken by the secondary index. Equal primary and
    /// secondary indicies indicates equal importance.
    ///
    /// These values are not expected to remain stable.
    var importanceIndex: (primary: Int, secondary: Int) { get }
}

extension Sequence where Element: ExperienceUpgradeSortable {
    /// Returns the elements sorted by importance order - i.e., each
    /// element in the returned array should be preferred for presention over
    /// its subsequent elements.
    func sortedByImportance() -> [Element] {
        sorted { lhs, rhs in
            if lhs.importanceIndex.primary == rhs.importanceIndex.primary {
                return lhs.importanceIndex.secondary < rhs.importanceIndex.secondary
            }

            return lhs.importanceIndex.primary < rhs.importanceIndex.primary
        }
    }
}

extension ExperienceUpgradeManifest: ExperienceUpgradeSortable {
    var importanceIndex: (primary: Int, secondary: Int) {
        switch self {
        case .introducingPins:
            return (0, 0)
        case .notificationPermissionReminder:
            return (1, 0)
        case .subscriptionMegaphone:
            return (2, 0)
        case .remoteMegaphone(let megaphone):
            // Remote megaphone manifests use higher numbers to indicate higher
            // priority, so we should invert their priority here.
            return (3, -1 * megaphone.manifest.priority)
        case .pinReminder:
            return (4, 0)
        case .contactPermissionReminder:
            return (5, 0)
        case .unrecognized:
            return (Int.max, Int.max)
        }
    }
}

extension ExperienceUpgrade: ExperienceUpgradeSortable {
    var importanceIndex: (primary: Int, secondary: Int) {
        manifest.importanceIndex
    }
}

// MARK: - Metadata

extension ExperienceUpgradeManifest {
    /// Whether this upgrade should not be shown to brand-new users.
    var skipForNewUsers: Bool {
        switch self {
        case
                .introducingPins,
                .subscriptionMegaphone,
                .remoteMegaphone:
            return false
        case
                .notificationPermissionReminder,
                .pinReminder,
                .contactPermissionReminder,
                .unrecognized:
            return true
        }
    }

    /// Whether we should save state for this upgrade in an ``ExperienceUpgrade``
    /// record. If we track state for this upgrade using other components, we
    /// may not need to persist ``ExperienceUpgrade`` state.
    var shouldSave: Bool {
        switch self {
        case
                .introducingPins,
                .pinReminder,
                .unrecognized:
            return false
        case
                .notificationPermissionReminder,
                .subscriptionMegaphone,
                .remoteMegaphone,
                .contactPermissionReminder:
            return true
        }
    }

    /// Whether we should mark this upgrade's corresponding ``ExperienceUpgrade``
    /// record as complete, if it exists. If we track state for this upgrade
    /// using other components, we may not need to mark the ``ExperienceUpgrade``
    /// as complete.
    var shouldComplete: Bool {
        switch self {
        case
                .introducingPins,
                .notificationPermissionReminder,
                .subscriptionMegaphone,
                .pinReminder,
                .contactPermissionReminder,
                .unrecognized:
            return false
        case .remoteMegaphone:
            return true
        }
    }

    /// The interval after snoozing during which we should not show the upgrade.
    var snoozeDuration: TimeInterval {
        switch self {
        case
                .introducingPins,
                .pinReminder:
            return 2 * kDayInterval
        case .notificationPermissionReminder:
            return 3 * kDayInterval
        case .subscriptionMegaphone:
            return RemoteConfig.subscriptionMegaphoneSnoozeInterval
        case .remoteMegaphone:
            // TODO: this property will be stored on the remote megaphone, eventually
            return kDayInterval
        case .contactPermissionReminder:
            return 30 * kDayInterval
        case .unrecognized:
            return Date.distantFuture.timeIntervalSince1970
        }
    }

    /// The number of days this upgrade should be shown, starting from the
    /// first time it is shown.
    var numberOfDaysToShowFor: Int {
        switch self {
        case
                .introducingPins,
                .notificationPermissionReminder,
                .subscriptionMegaphone,
                .pinReminder,
                .contactPermissionReminder:
            return Int.max
        case .remoteMegaphone(let megaphone):
            return megaphone.manifest.showForNumberOfDays
        case .unrecognized:
            return 0
        }
    }

    /// The interval immediately after registration during which we should not
    /// show the upgrade.
    private var delayAfterRegistration: TimeInterval {
        switch self {
        case
                .notificationPermissionReminder,
                .contactPermissionReminder:
            return kDayInterval
        case .introducingPins:
            return 2 * kHourInterval
        case .subscriptionMegaphone:
            return 5 * kDayInterval
        case .remoteMegaphone:
            // Controlled via conditional check
            return 0
        case .pinReminder:
            return 8 * kHourInterval
        case .unrecognized:
            return .infinity
        }
    }

    /// The date after which the upgrade should no longer be shown.
    private var expirationDate: Date {
        switch self {
        case
                .introducingPins,
                .notificationPermissionReminder,
                .subscriptionMegaphone,
                .pinReminder,
                .contactPermissionReminder:
            return Date.distantFuture
        case .remoteMegaphone(let megaphone):
            return Date(timeIntervalSince1970: TimeInterval(megaphone.manifest.dontShowAfter))
        case .unrecognized:
            return Date.distantPast
        }
    }

    /// Whether we should show this upgrade on linked devices.
    private var showOnLinkedDevices: Bool {
        switch self {
        case
                .introducingPins,
                .pinReminder,
                .unrecognized:
            return false
        case
                .notificationPermissionReminder,
                .subscriptionMegaphone,
                .contactPermissionReminder:
            return true
        case
                .remoteMegaphone:
            // Controlled by conditional check
            return true
        }
    }
}

// MARK: - Should we show this upgrade

extension ExperienceUpgradeManifest {
    func shouldBeShown(transaction: SDSAnyReadTransaction) -> Bool {
        if
            let registrationDate = tsAccountManager.registrationDate(with: transaction),
            Date().timeIntervalSince(registrationDate) < delayAfterRegistration
        {
            // We have not waited long enough after registration to show this
            // upgrade.
            return false
        }

        guard Date() < expirationDate else {
            // We should not show an expired upgrade.
            return false
        }

        guard showOnLinkedDevices || tsAccountManager.isRegisteredPrimaryDevice else {
            // We are a linked device, which should not show this upgrade.
            return false
        }

        return Self.checkPreconditions(specificTo: self, transaction: transaction)
    }

    private static func checkPreconditions(specificTo enumCase: ExperienceUpgradeManifest, transaction: SDSAnyReadTransaction) -> Bool {
        switch enumCase {
        case .introducingPins:
            return checkPreconditionsForIntroducingPins(transaction: transaction)
        case .notificationPermissionReminder:
            return checkPreconditionsForNotificationsPermissionsReminder()
        case .subscriptionMegaphone:
            return checkPreconditionsForSubscriptionMegaphone(transaction: transaction)
        case .remoteMegaphone(let megaphone):
            return checkPreconditionsForRemoteMegaphone(withManifest: megaphone.manifest)
        case .pinReminder:
            return checkPreconditionsForPinReminder(transaction: transaction)
        case .contactPermissionReminder:
            return checkPreconditionsForContactsPermissionReminder()
        case .unrecognized:
            return false
        }
    }

    private static func checkPreconditionsForIntroducingPins(transaction: SDSAnyReadTransaction) -> Bool {
        // The PIN setup flow requires an internet connection and you to not already have a PIN
        if
            RemoteConfig.kbs,
            reachabilityManager.isReachable,
            !KeyBackupService.hasMasterKey(transaction: transaction)
        {
            return true
        }

        return false
    }

    private static func checkPreconditionsForNotificationsPermissionsReminder() -> Bool {
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
    }

    private static func checkPreconditionsForSubscriptionMegaphone(transaction: SDSAnyReadTransaction) -> Bool {
        // Show the subscription megaphone IFF:
        // - It's remotely enabled
        // - The user has no / an expired subscription
        // - Their last subscription has been expired for more than 2 weeks

        guard RemoteConfig.subscriptionMegaphone else {
            return false
        }

        let timeSinceExpiration = subscriptionManager.timeSinceLastSubscriptionExpiration(transaction: transaction)
        return timeSinceExpiration > (2 * kWeekInterval)
    }

    private static func checkPreconditionsForRemoteMegaphone(withManifest manifest: RemoteMegaphoneModel.Manifest) -> Bool {
        guard
            AppVersion.compare(
                manifest.minAppVersion,
                with: appVersion.currentAppVersion4
            ) != .orderedDescending
        else {
            Logger.debug("App version \(appVersion.currentAppVersion4) lower than required \(manifest.minAppVersion)!")
            return false
        }

        guard Date().timeIntervalSince1970 > TimeInterval(manifest.dontShowBefore) else {
            Logger.debug("Remote megaphone should not be shown until later!")
            return false
        }

        guard RemoteConfig.isCountryCodeBucketEnabled(
            csvString: manifest.countries,
            key: manifest.id,
            csvDescription: "remoteMegaphoneCountries_\(manifest.id)"
        ) else {
            Logger.debug("Remote megaphone not enabled for this user, by country code!")
            return false
        }

        if let conditionalCheck = manifest.conditionalCheck {
            switch conditionalCheck {
            case .unrecognized(let conditionalId):
                Logger.warn("Found unrecognized conditional check with ID \(conditionalId), bailing.")
                return false
            }
        }

        // Hard-coding to `false` since we don't yet have UI to show megaphones.
        // TODO: once we have UI to show remote megaphones, toggle this to `true`.
        return false
    }

    private static func checkPreconditionsForPinReminder(transaction: SDSAnyReadTransaction) -> Bool {
        return OWS2FAManager.shared.isDueForV2Reminder(transaction: transaction)
    }

    private static func checkPreconditionsForContactsPermissionReminder() -> Bool {
        return CNContactStore.authorizationStatus(for: CNEntityType.contacts) != .authorized
    }
}
