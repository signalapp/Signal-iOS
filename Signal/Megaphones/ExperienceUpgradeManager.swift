//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import SignalServiceKit
import SignalUI

class ExperienceUpgradeManager {

    private enum StoreKeys {
        static let lastMegaphoneDismissDate = "lastExperienceUpgradeDismissDate"
    }

    private static var lastPresentedMegaphone: Megaphone?
    private static var lastPresentedMegaphoneView: MegaphoneView?

    private static var accountKeyStore: AccountKeyStore { DependenciesBridge.shared.accountKeyStore }
    private static let attachmentStore = AttachmentStore()
    private static let backupSettingsStore = BackupSettingsStore()
    private static let dateProvider: DateProvider = { Date() }
    private static var db: DB { DependenciesBridge.shared.db }
    private static var deviceStore: OWSDeviceStore { DependenciesBridge.shared.deviceStore }
    private static var donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore { DependenciesBridge.shared.donationReceiptCredentialResultStore }
    private static let experienceUpgradeStore = ExperienceUpgradeStore()
    private static var inactiveLinkedDeviceFinder: InactiveLinkedDeviceFinder { DependenciesBridge.shared.inactiveLinkedDeviceFinder }
    private static var inactivePrimaryDeviceStore: InactivePrimaryDeviceStore { DependenciesBridge.shared.inactivePrimaryDeviceStore }
    private static let keyValueStore = NewKeyValueStore(collection: "ExperienceUpgradeManager")
    private static var localUsernameManager: LocalUsernameManager { DependenciesBridge.shared.localUsernameManager }
    private static var networkManager: NetworkManager { SSKEnvironment.shared.networkManagerRef }
    private static var ows2FAManager: OWS2FAManager { SSKEnvironment.shared.ows2FAManagerRef }
    private static var profileManager: ProfileManager { SSKEnvironment.shared.profileManagerRef }
    private static var reachabilityManager: SSKReachabilityManager { SSKEnvironment.shared.reachabilityManagerRef }
    private static var remoteConfigManager: RemoteConfigManager { SSKEnvironment.shared.remoteConfigManagerRef }
    private static var storageServiceManager: StorageServiceManager { SSKEnvironment.shared.storageServiceManagerRef }
    private static var subscriptionConfigManager: SubscriptionConfigManager { DependenciesBridge.shared.subscriptionConfigManager }
    private static var usernameEducationManager: UsernameEducationManager { DependenciesBridge.shared.usernameEducationManager }
    private static var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }
    private static var usernameSelectionCoordinator: UsernameSelectionCoordinator {
        UsernameSelectionCoordinator(
            currentUsername: nil,
            context: UsernameSelectionCoordinator.Context(
                databaseStorage: db,
                networkManager: networkManager,
                storageServiceManager: storageServiceManager,
                usernameEducationManager: usernameEducationManager,
                localUsernameManager: localUsernameManager,
            ),
        )
    }

    static func reconcilePresentedExperienceUpgrade(fromViewController: UIViewController) {
        let now = Date()
        var shouldClearNewDeviceNotification = false
        var shouldClearBackupsEnabledDetails = false

        let lastMegaphoneDismissDate: Date
        let nextMegaphone: Megaphone?
        (
            lastMegaphoneDismissDate,
            nextMegaphone,
        ) = db.read { tx in
            guard
                let registeredState = try? tsAccountManager.registeredState(tx: tx),
                let registrationDate = tsAccountManager.registrationDate(tx: tx)
            else {
                return (.distantPast, nil)
            }

            let lastMegaphoneDismissDate = keyValueStore.fetchValue(
                Date.self,
                forKey: StoreKeys.lastMegaphoneDismissDate,
                tx: tx,
            ) ?? .distantPast

            var nextMegaphone: Megaphone?
            for upgrade in allKnownExperienceUpgrades(tx: tx) {
                if nextMegaphone != nil {
                    break
                }

                guard
                    !upgrade.isComplete,
                    !upgrade.isSnoozed(now: now),
                    !upgrade.hasPassedNumberOfDaysToShow(now: now),
                    now.timeIntervalSince(registrationDate) > upgrade.manifest.delayAfterRegistration,
                    now < upgrade.manifest.expirationDate,
                    (registeredState.isPrimary || upgrade.manifest.showOnLinkedDevices)
                else {
                    continue
                }

                switch upgrade.manifest {
                case .introducingPins:
                    if checkPreconditionsForIntroducingPins(tx: tx) {
                        nextMegaphone = IntroducingPinsMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .notificationPermissionReminder:
                    if checkPreconditionsForNotificationsPermissionsReminder() {
                        nextMegaphone = NotificationPermissionReminderMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .newLinkedDeviceNotification:
                    switch checkPreconditionsForNewLinkedDeviceNotification(tx: tx) {
                    case .display(let mostRecentlyLinkedDeviceDetails):
                        nextMegaphone = NewLinkedDeviceNotificationMegaphone(
                            db: db,
                            deviceStore: deviceStore,
                            experienceUpgrade: upgrade,
                            mostRecentlyLinkedDeviceDetails: mostRecentlyLinkedDeviceDetails,
                        )
                    case .skip:
                        break
                    case .clearNotification:
                        shouldClearNewDeviceNotification = true
                    }
                case .createUsernameReminder:
                    if checkPreconditionsForCreateUsernameReminder(tx: tx) {
                        nextMegaphone = CreateUsernameMegaphone(
                            usernameSelectionCoordinator: usernameSelectionCoordinator,
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .remoteMegaphone(let remoteMegaphoneModel):
                    if
                        checkPreconditionsForRemoteMegaphone(
                            remoteMegaphoneModel: remoteMegaphoneModel,
                            now: now,
                            tx: tx,
                        )
                    {
                        nextMegaphone = RemoteMegaphone(
                            experienceUpgrade: upgrade,
                            remoteMegaphoneModel: remoteMegaphoneModel,
                            fromViewController: fromViewController,
                        )
                    }
                case .inactiveLinkedDeviceReminder:
                    if let inactiveLinkedDevice = checkPreconditionsForInactiveLinkedDeviceReminder(tx: tx) {
                        nextMegaphone = InactiveLinkedDeviceReminderMegaphone(
                            inactiveLinkedDevice: inactiveLinkedDevice,
                            fromViewController: fromViewController,
                            experienceUpgrade: upgrade,
                        )
                    }
                case .inactivePrimaryDeviceReminder:
                    if checkPreconditionsForInactivePrimaryDeviceReminder(tx: tx) {
                        nextMegaphone = InactivePrimaryDeviceReminderMegaphone(
                            fromViewController: fromViewController,
                            experienceUpgrade: upgrade,
                        )
                    }
                case .pinReminder:
                    if checkPreconditionsForPinReminder(tx: tx) {
                        nextMegaphone = PinReminderMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .contactPermissionReminder:
                    if checkPreconditionsForContactsPermissionReminder() {
                        nextMegaphone = ContactPermissionReminderMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .backupKeyReminder:
                    if checkPreconditionsForRecoveryKeyReminder(tx: tx) {
                        nextMegaphone = RecoveryKeyReminderMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .backupsUpsellReminder:
                    switch checkPreconditionsForBackupsUpsellReminder(
                        experienceUpgrade: upgrade,
                        tx: tx,
                    ) {
                    case nil:
                        break
                    case .genericEnable:
                        nextMegaphone = BackupsGenericEnableMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    case .neverLoseAMessage:
                        nextMegaphone = BackupsNeverLoseAMessageMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    case .backUpYourMedia(let backupSubscriptionConfiguration):
                        nextMegaphone = BackupsBackUpYourMediaMegaphone(
                            backupSubscriptionConfiguration: backupSubscriptionConfiguration,
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    case .saveSpace(let areBackupsEnabled):
                        nextMegaphone = BackupsSaveSpaceMegaphone(
                            areBackupsEnabled: areBackupsEnabled,
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                        )
                    }
                case .backupsEnabledRecentlyNotification:
                    switch checkPreconditionsForBackupsEnabledRecentlyNotification(
                        now: now,
                        tx: tx,
                    ) {
                    case .display(let lastBackupEnabledDetails):
                        nextMegaphone = BackupsEnabledRecentlyNotificationMegaphone(
                            experienceUpgrade: upgrade,
                            fromViewController: fromViewController,
                            backupsEnabledTime: lastBackupEnabledDetails.enabledTime,
                            db: db,
                            backupSettingsStore: backupSettingsStore,
                        )
                    case .skip:
                        break
                    case .clearStoredDetails:
                        shouldClearBackupsEnabledDetails = true
                    }
                case .unrecognized:
                    break
                }
            }

            return (
                lastMegaphoneDismissDate,
                nextMegaphone,
            )
        }

        if shouldClearNewDeviceNotification {
            db.write { tx in
                deviceStore.clearMostRecentlyLinkedDeviceDetails(tx: tx)
            }
        }

        if shouldClearBackupsEnabledDetails {
            db.write { tx in
                backupSettingsStore.clearLastBackupEnabledDetails(tx: tx)
            }
        }

        guard let nextMegaphone else {
            _ = dismissLastPresented(now: now)
            return
        }

        if
            let lastPresentedMegaphone,
            type(of: lastPresentedMegaphone) == type(of: nextMegaphone)
        {
            return
        }

        // If we're dismissing a megaphone, don't immediately present another.
        if dismissLastPresented(now: now) {
            return
        } else if
            now.timeIntervalSince(lastMegaphoneDismissDate) > .day
        {
            let megaphoneView = nextMegaphone.buildView()
            megaphoneView.present(fromViewController: fromViewController)

            lastPresentedMegaphone = nextMegaphone
            lastPresentedMegaphoneView = megaphoneView

            db.write { tx in
                experienceUpgradeStore.markAsViewed(
                    experienceUpgrade: nextMegaphone.experienceUpgrade,
                    tx: tx,
                )
            }
        }
    }

    /// Returns an array of all recognized ``ExperienceUpgrade``s. Contains the
    /// persisted record if one exists and is applicable, and an in-memory
    /// model otherwise.
    private static func allKnownExperienceUpgrades(
        tx: DBReadTransaction,
    ) -> [ExperienceUpgrade] {
        var experienceUpgrades = [ExperienceUpgrade]()
        var localManifestsWithoutRecords = ExperienceUpgradeManifest.wellKnownLocalUpgradeManifests

        // Load any experience upgrades with persisted records...
        experienceUpgradeStore.enumerateExperienceUpgrades(tx: tx) { experienceUpgrade in
            if case .unrecognized = experienceUpgrade.manifest {
                // Ignore any no-longer-recognized records.
                return
            }

            guard experienceUpgrade.manifest.shouldSave else {
                // Ignore saved records that we no longer persist.
                return
            }

            experienceUpgrades.append(experienceUpgrade)
            localManifestsWithoutRecords.remove(experienceUpgrade.manifest)
        }

        // ...and instantiate new (in-memory) models for any local manifests
        // without persisted records.
        for localManifest in localManifestsWithoutRecords {
            experienceUpgrades.append(ExperienceUpgrade.makeNew(withManifest: localManifest))
        }

        return ExperienceUpgradeManifest.sortedByImportance(experienceUpgrades)
    }

    /// - Returns
    /// Whether or not we dismissed a megaphone.
    private static func dismissLastPresented(now: Date) -> Bool {
        guard lastPresentedMegaphone != nil, let lastPresentedMegaphoneView else {
            return false
        }

        db.write { tx in
            keyValueStore.writeValue(
                now,
                forKey: StoreKeys.lastMegaphoneDismissDate,
                tx: tx,
            )
        }

        lastPresentedMegaphoneView.dismiss()
        self.lastPresentedMegaphone = nil
        self.lastPresentedMegaphoneView = nil
        return true
    }

    // MARK: - Megaphone Preconditions

    private static func checkPreconditionsForIntroducingPins(
        tx: DBReadTransaction,
    ) -> Bool {
        // The PIN setup flow requires an internet connection and you to not already have a PIN
        if
            reachabilityManager.isReachable,
            tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
            accountKeyStore.getMasterKey(tx: tx) == nil
        {
            return true
        }

        return false
    }

    private static func checkPreconditionsForNotificationsPermissionsReminder() -> Bool {
        let (promise, future) = Promise<Bool>.pending()

        DispatchQueue.global(qos: .userInitiated).async {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
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

    private enum NewLinkedDeviceNotificationResult {
        case display(MostRecentlyLinkedDeviceDetails)
        case skip
        case clearNotification
    }

    private static func checkPreconditionsForNewLinkedDeviceNotification(
        tx: DBReadTransaction,
    ) -> NewLinkedDeviceNotificationResult {
        guard
            let mostRecentlyLinkedDeviceDetails = deviceStore.mostRecentlyLinkedDeviceDetails(tx: tx)
        else {
            return .skip
        }

        // No need to show a megaphone if notifications are on, which we happen
        // to already check for the notification permission megaphone.
        return if !checkPreconditionsForNotificationsPermissionsReminder() {
            .clearNotification
        } else if Date() > mostRecentlyLinkedDeviceDetails.shouldRemindUserAfter {
            .display(mostRecentlyLinkedDeviceDetails)
        } else {
            .skip
        }
    }

    private enum BackupsEnabledRecentlyNotificationResult {
        case display(BackupSettingsStore.LastBackupEnabledDetails)
        case skip
        case clearStoredDetails
    }

    private static func checkPreconditionsForBackupsEnabledRecentlyNotification(
        now: Date,
        tx: DBReadTransaction,
    ) -> BackupsEnabledRecentlyNotificationResult {
        guard let lastBackupEnabledDetails = backupSettingsStore.lastBackupEnabledDetails(tx: tx) else {
            return .skip
        }

        // Don't show the megaphone if notifications are enabled, we'll send
        // a notification instead. Clear the stored details so we don't show
        // a stale megaphone in the future.
        guard checkPreconditionsForNotificationsPermissionsReminder() else {
            return .clearStoredDetails
        }

        if now > lastBackupEnabledDetails.shouldRemindUserAfter {
            return .display(lastBackupEnabledDetails)
        } else {
            return .skip
        }
    }

    private static func checkPreconditionsForCreateUsernameReminder(
        tx: DBReadTransaction,
    ) -> Bool {
        guard
            localUsernameManager.usernameState(
                tx: tx,
            ).isExplicitlyUnset
        else {
            // If we have a username, do not show the reminder.
            return false
        }
        if tsAccountManager.phoneNumberDiscoverability(tx: tx).orDefault.isDiscoverable {
            // If phone number discovery is enabled, do not prompt to create a
            // username.
            return false
        }

        /// The elapsed interval since the user disabled phone number
        /// discovery. Note that we need to invert the sign as this date will
        /// be in the past.
        let timeIntervalSinceDisabledDiscovery = tsAccountManager
            .lastSetIsDiscoverableByPhoneNumber(tx: tx)
            .timeIntervalSinceNow * -1

        let requiredDelayAfterDisablingDiscovery: TimeInterval = 3 * .day

        return timeIntervalSinceDisabledDiscovery > requiredDelayAfterDisablingDiscovery
    }

    private static func checkPreconditionsForInactiveLinkedDeviceReminder(
        tx: DBReadTransaction,
    ) -> InactiveLinkedDevice? {
        return inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: tx)
    }

    private static func checkPreconditionsForInactivePrimaryDeviceReminder(
        tx: DBReadTransaction,
    ) -> Bool {
        return inactivePrimaryDeviceStore.valueForInactivePrimaryDeviceAlert(transaction: tx)
    }

    private static func checkPreconditionsForPinReminder(
        tx: DBReadTransaction,
    ) -> Bool {
        return ows2FAManager.isDueForV2Reminder(transaction: tx)
    }

    private static func checkPreconditionsForContactsPermissionReminder() -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return false
        case .restricted:
            // If this isn't allowed by device policy, don't nag.
            return false
        case .denied, .notDetermined:
            return true
        @unknown default:
            return false
        }
    }

    private static func checkPreconditionsForRecoveryKeyReminder(
        tx: DBReadTransaction,
    ) -> Bool {
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            return false
        }

        switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled, .disabling:
            return false
        case .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        guard let firstBackupDate = backupSettingsStore.lastBackupDetails(tx: tx)?.firstBackupDate else {
            return false
        }

        let lastReminderDate = backupSettingsStore.lastRecoveryKeyReminderDate(tx: tx)

        let fourteenDaysAgo = Date().addingTimeInterval(-14 * .day)
        guard let lastReminderDate else {
            // Return true if the first backup happened over 2 weeks ago
            // and we haven't shown a reminder yet.
            return firstBackupDate < fourteenDaysAgo
        }

        // Return true if there's been no reminder within 6 months.
        return lastReminderDate < Date().addingTimeInterval(-6 * .month)
    }

    private enum BackupsUpsellResult {
        case genericEnable
        case neverLoseAMessage
        case backUpYourMedia(backupSubscriptionConfiguration: BackupSubscriptionConfiguration)
        case saveSpace(areBackupsEnabled: Bool)
    }

    private static func checkPreconditionsForBackupsUpsellReminder(
        experienceUpgrade: ExperienceUpgrade,
        tx: DBReadTransaction,
    ) -> BackupsUpsellResult? {
        guard
            remoteConfigManager.currentConfig().backupsMegaphone,
            tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice
        else {
            return nil
        }

        if
            experienceUpgrade.firstViewedTimestamp == 0,
            !backupSettingsStore.haveBackupsEverBeenEnabled(tx: tx)
        {
            return .genericEnable
        }

        let areBackupsEnabled: Bool
        switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled, .disabling:
            areBackupsEnabled = false
        case .free:
            areBackupsEnabled = true
        case .paid, .paidAsTester, .paidExpiringSoon:
            // We never need to show an upsell to paid-tier users.
            return nil
        }
        // At this point, if Backups are enabled they're free-tier.

        // Don't show if they don't have much to back up.
        let clampedMessageCount = InteractionFinder.outgoingAndIncomingMessageCount(limit: 1000, tx: tx)
        guard clampedMessageCount >= 1000 else {
            return nil
        }

        let attachmentsSize = attachmentStore.sumEncryptedByteCount(stopAfter: .gigabyte, tx: tx)
        if attachmentsSize < .gigabyte {
            if areBackupsEnabled {
                let backupSubscriptionConfiguration = subscriptionConfigManager.backupConfigurationOrDefault(tx: tx)
                return .backUpYourMedia(backupSubscriptionConfiguration: backupSubscriptionConfiguration)
            } else {
                return .neverLoseAMessage
            }
        } else {
            return .saveSpace(areBackupsEnabled: areBackupsEnabled)
        }
    }

    // MARK: Remote megaphone

    private static func checkPreconditionsForRemoteMegaphone(
        remoteMegaphoneModel: RemoteMegaphoneModel,
        now: Date,
        tx: DBReadTransaction,
    ) -> Bool {
        let manifest = remoteMegaphoneModel.manifest
        let translation = remoteMegaphoneModel.translation

        let minimumVersion = AppVersionNumber(manifest.minAppVersion)
        let currentVersion = AppVersionNumber(AppVersionImpl.shared.currentAppVersion)
        guard currentVersion >= minimumVersion else {
            return false
        }

        guard now.timeIntervalSince1970 > TimeInterval(manifest.dontShowBefore) else {
            return false
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            return false
        }

        guard
            RemoteConfig.isCountryCodeBucketEnabled(
                csvString: manifest.countries,
                key: manifest.id,
                localIdentifiers: localIdentifiers,
            )
        else {
            return false
        }

        guard
            validateRemoteMegaphone(
                conditionalCheck: manifest.conditionalCheck,
                tx: tx,
            )
        else {
            return false
        }

        guard
            validateRemoteMegaphone(
                action: manifest.primaryAction,
                withText: translation.primaryActionText,
            )
        else {
            return false
        }

        guard
            validateRemoteMegaphone(
                action: manifest.secondaryAction,
                withText: translation.secondaryActionText,
            )
        else {
            return false
        }

        return true
    }

    private static func validateRemoteMegaphone(
        conditionalCheck: RemoteMegaphoneModel.Manifest.ConditionalCheck?,
        tx: DBReadTransaction,
    ) -> Bool {
        guard let conditionalCheck else {
            // Having no conditional check is valid.
            return true
        }

        switch conditionalCheck {
        case .standardDonate:
            if profileManager.localUserProfile(tx: tx)?.hasBadge == true {
                // Fail the check if we currently have a badge.
                return false
            } else if
                donationReceiptCredentialResultStore
                    .hasAnyPaymentsStillProcessing(tx: tx)
            {
                // Fail the check if we have any in-progress payments.
                return false
            }

            return true
        case .internalUser:
            // Show this megaphone to all internal users, even if they already
            // have a badge.
            return DebugFlags.internalMegaphoneEligible
        case .unrecognized(let conditionalId):
            Logger.warn("Found unrecognized conditional check with ID \(conditionalId), bailing.")
            return false
        }
    }

    private static func validateRemoteMegaphone(
        action: RemoteMegaphoneModel.Manifest.Action?,
        withText text: String?,
    ) -> Bool {
        guard let action else {
            // Having no action is valid...
            return true
        }

        guard action.isRecognized else {
            // ...but we need to recognize it...
            Logger.warn("Found unrecognized action with ID \(action.actionId), bailing.")
            return false
        }

        guard text != nil else {
            // ...and have text for it.
            Logger.warn("Missing action text for action \(action.actionId)")
            return false
        }

        return true
    }
}

// MARK: -

private extension RemoteMegaphoneModel.Manifest.Action {
    var isRecognized: Bool {
        if case .unrecognized = self {
            return false
        }

        return true
    }
}

// MARK: -

private extension DonationReceiptCredentialResultStore {
    /// Do we have any payments that have been initiated, but are still
    /// in-progress?
    func hasAnyPaymentsStillProcessing(tx: DBReadTransaction) -> Bool {
        for requestErrorMode in Mode.allCases {
            if
                let requestError = getRequestError(errorMode: requestErrorMode, tx: tx),
                case .paymentStillProcessing = requestError.errorCode
            {
                return true
            }
        }

        return false
    }
}
