//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient
public import SignalServiceKit

extension RegistrationCoordinatorImpl {

    public enum Shims {
        public typealias ContactsManager = _RegistrationCoordinator_ContactsManagerShim
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreShim
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerShim
        public typealias IdentityManager = _RegistrationCoordinator_IdentityManagerShim
        public typealias MessagePipelineSupervisor = _RegistrationCoordinator_MessagePipelineSupervisorShim
        public typealias MessageProcessor = _RegistrationCoordinator_MessageProcessorShim
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerShim
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerShim
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerShim
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerShim
        public typealias StorageServiceManager = _RegistrationCoordinator_StorageServiceManagerShim
        public typealias TimeoutProvider = _RegistrationCoordinator_TimeoutProviderShim
        public typealias UDManager = _RegistrationCoordinator_UDManagerShim
        public typealias UsernameApiClient = _RegistrationCoordinator_UsernameApiClientShim
    }
    public enum Wrappers {
        public typealias ContactsManager = _RegistrationCoordinator_ContactsManagerWrapper
        public typealias ContactsStore = _RegistrationCoordinator_CNContactsStoreWrapper
        public typealias ExperienceManager = _RegistrationCoordinator_ExperienceManagerWrapper
        public typealias IdentityManager = _RegistrationCoordinator_IdentityManagerWrapper
        public typealias MessagePipelineSupervisor = _RegistrationCoordinator_MessagePipelineSupervisorWrapper
        public typealias MessageProcessor = _RegistrationCoordinator_MessageProcessorWrapper
        public typealias OWS2FAManager = _RegistrationCoordinator_OWS2FAManagerWrapper
        public typealias ProfileManager = _RegistrationCoordinator_ProfileManagerWrapper
        public typealias PushRegistrationManager = _RegistrationCoordinator_PushRegistrationManagerWrapper
        public typealias ReceiptManager = _RegistrationCoordinator_ReceiptManagerWrapper
        public typealias StorageServiceManager = _RegistrationCoordinator_StorageServiceManagerWrapper
        public typealias TimeoutProvider = _RegistrationCoordinator_TimeoutProviderWrapper
        public typealias UDManager = _RegistrationCoordinator_UDManagerWrapper
        public typealias UsernameApiClient = _RegistrationCoordinator_UsernameApiClientWrapper
    }
}

// MARK: OWSContactsManager

public protocol _RegistrationCoordinator_ContactsManagerShim {

    func fetchSystemContactsOnceIfAlreadyAuthorized()
}

public class _RegistrationCoordinator_ContactsManagerWrapper: _RegistrationCoordinator_ContactsManagerShim {

    private let manager: OWSContactsManager
    public init(_ manager: OWSContactsManager) { self.manager = manager }

    public func fetchSystemContactsOnceIfAlreadyAuthorized() {
        manager.fetchSystemContactsOnceIfAlreadyAuthorized()
    }
}

// MARK: CNContacts

public protocol _RegistrationCoordinator_CNContactsStoreShim {

    func needsContactsAuthorization() -> Bool

    func requestContactsAuthorization() async
}

public class _RegistrationCoordinator_CNContactsStoreWrapper: _RegistrationCoordinator_CNContactsStoreShim {

    public init() {}

    public func needsContactsAuthorization() -> Bool {
        return CNContactStore.authorizationStatus(for: .contacts) == .notDetermined
    }

    public func requestContactsAuthorization() async {
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
                if granted {
                    Logger.info("User granted contacts permission")
                } else {
                    // Unfortunately, we can't easily disambiguate "not granted" and
                    // "other error".
                    Logger.warn("User denied contacts permission or there was an error. Error: \(String(describing: error))")
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - ExperienceManager

public protocol _RegistrationCoordinator_ExperienceManagerShim {

    func clearIntroducingPinsExperience(_ tx: DBWriteTransaction)

    func enableAllGetStartedCards(_ tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_ExperienceManagerWrapper: _RegistrationCoordinator_ExperienceManagerShim {

    public init() {}

    public func clearIntroducingPinsExperience(_ tx: DBWriteTransaction) {
        ExperienceUpgradeManager.clearExperienceUpgrade(.introducingPins, transaction: tx)
    }

    public func enableAllGetStartedCards(_ tx: DBWriteTransaction) {
        GetStartedBannerViewController.enableAllCards(writeTx: tx)
    }
}

// MARK: - IdentityManager

public protocol _RegistrationCoordinator_IdentityManagerShim {
    func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_IdentityManagerWrapper: _RegistrationCoordinator_IdentityManagerShim {
    private let identityManager: OWSIdentityManager
    public init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    public func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        identityManager.setIdentityKeyPair(keyPair, for: identity, tx: tx)
    }
}

// MARK: - MessagePipelineSupervisor

public protocol _RegistrationCoordinator_MessagePipelineSupervisorShim {

    func suspendMessageProcessingWithoutHandle(for: MessagePipelineSupervisor.Suspension)

    func unsuspendMessageProcessing(for: MessagePipelineSupervisor.Suspension)
}

public class _RegistrationCoordinator_MessagePipelineSupervisorWrapper: _RegistrationCoordinator_MessagePipelineSupervisorShim {

    private let supervisor: MessagePipelineSupervisor

    public init(_ supervisor: MessagePipelineSupervisor) {
        self.supervisor = supervisor
    }

    public func suspendMessageProcessingWithoutHandle(for suspension: MessagePipelineSupervisor.Suspension) {
        supervisor.suspendMessageProcessingWithoutHandle(for: suspension)
    }

    public func unsuspendMessageProcessing(for suspension: MessagePipelineSupervisor.Suspension) {
        supervisor.unsuspendMessageProcessing(for: suspension)
    }
}

// MARK: - MessageProcessor

public protocol _RegistrationCoordinator_MessageProcessorShim {
    func waitForFetchingAndProcessing() -> Guarantee<Void>
}

public class _RegistrationCoordinator_MessageProcessorWrapper: _RegistrationCoordinator_MessageProcessorShim {

    private let processor: MessageProcessor

    public init(_ processor: MessageProcessor) {
        self.processor = processor
    }

    public func waitForFetchingAndProcessing() -> Guarantee<Void> {
        return Guarantee.wrapAsync { [processor] in
            do throws(CancellationError) {
                try await processor.waitForFetchingAndProcessing()
            } catch {
                owsFail("Guarantees can't be canceled.")
            }
        }
    }
}

// MARK: - OWS2FAManager

public protocol _RegistrationCoordinator_OWS2FAManagerShim {

    func pinCode(_ tx: DBReadTransaction) -> String?

    func clearLocalPinCode(_ tx: DBWriteTransaction)

    func isReglockEnabled(_ tx: DBReadTransaction) -> Bool

    func markPinEnabled(pin: String, resetReminderInterval: Bool, tx: DBWriteTransaction)

    func markRegistrationLockEnabled(_  tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_OWS2FAManagerWrapper: _RegistrationCoordinator_OWS2FAManagerShim {

    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(_ tx: DBReadTransaction) -> String? {
        return manager.pinCode(transaction: tx)
    }

    public func clearLocalPinCode(_ tx: DBWriteTransaction) {
        return manager.clearLocalPinCode(transaction: tx)
    }

    public func isReglockEnabled(_ tx: DBReadTransaction) -> Bool {
        return manager.isRegistrationLockV2Enabled(transaction: tx)
    }

    public func markPinEnabled(pin: String, resetReminderInterval: Bool, tx: DBWriteTransaction) {
        manager.markEnabled(
            pin: pin,
            resetReminderInterval: resetReminderInterval,
            transaction: tx
        )
    }

    public func markRegistrationLockEnabled(_ tx: DBWriteTransaction) {
        manager.markRegistrationLockV2Enabled(transaction: tx)
    }
}

// MARK: - ProfileManager

public protocol _RegistrationCoordinator_ProfileManagerShim {

    func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile?

    // NOTE: non-optional because OWSProfileManager generates a random key
    // if one doesn't already exist.

    func updateLocalProfile(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void>

    func scheduleReuploadLocalProfile(authedAccount: AuthedAccount)
}

public class _RegistrationCoordinator_ProfileManagerWrapper: _RegistrationCoordinator_ProfileManagerShim {

    private let manager: ProfileManager
    public init(_ manager: ProfileManager) { self.manager = manager }

    public func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile? {
        return manager.localUserProfile(tx: tx)
    }

    public func updateLocalProfile(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return manager.updateLocalProfile(
            profileGivenName: .setTo(givenName),
            profileFamilyName: .setTo(familyName),
            profileBio: .setTo(nil),
            profileBioEmoji: .setTo(nil),
            profileAvatarData: .setTo(avatarData),
            visibleBadgeIds: .setTo([]),
            unsavedRotatedProfileKey: nil,
            userProfileWriter: .registration,
            authedAccount: authedAccount,
            tx: tx
        )
    }

    public func scheduleReuploadLocalProfile(authedAccount: AuthedAccount) {
        Task {
            await DependenciesBridge.shared.db.awaitableWrite { tx in
                _ = manager.reuploadLocalProfile(
                    unsavedRotatedProfileKey: nil,
                    mustReuploadAvatar: true,
                    authedAccount: authedAccount,
                    tx: tx
                )
            }
        }
    }
}

// MARK: - PushRegistrationManager

extension Registration {
    public enum RequestPushTokensResult {
        case success(RegistrationRequestFactory.ApnRegistrationId)
        case pushUnsupported(description: String)
        case timeout
        case genericError(Error)
    }

    public enum SyncPushTokensResult {
        case success
        case pushUnsupported(description: String)
        case networkError
        case genericError(Error)
    }
}

public protocol _RegistrationCoordinator_PushRegistrationManagerShim {

    func needsNotificationAuthorization() async -> Bool

    func registerUserNotificationSettings() async

    func requestPushToken() async -> Registration.RequestPushTokensResult

    func receivePreAuthChallengeToken() async -> String

    func clearPreAuthChallengeToken()
}

public class _RegistrationCoordinator_PushRegistrationManagerWrapper: _RegistrationCoordinator_PushRegistrationManagerShim {

    private let manager: PushRegistrationManager
    public init(_ manager: PushRegistrationManager) { self.manager = manager }

    public func needsNotificationAuthorization() async -> Bool {
        return await manager.needsNotificationAuthorization()
    }

    public func registerUserNotificationSettings() async {
        await manager.registerUserNotificationSettings()
    }

    public func requestPushToken() async -> Registration.RequestPushTokensResult {
        do {
            let result = try await manager.requestPushTokens(forceRotation: false, timeOutEventually: true)
            return .success(result)
        } catch PushRegistrationError.pushNotSupported(let description) {
            return .pushUnsupported(description: description)
        } catch PushRegistrationError.timeout {
            return .timeout
        } catch {
            return .genericError(error)
        }
    }

    public func receivePreAuthChallengeToken() async -> String {
        return await manager.receivePreAuthChallengeToken()
    }

    public func clearPreAuthChallengeToken() {
        manager.clearPreAuthChallengeToken()
    }
}

// MARK: - ReceiptManager

public protocol _RegistrationCoordinator_ReceiptManagerShim {

    func setAreReadReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction)
    func setAreStoryViewedReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction)
}

public class _RegistrationCoordinator_ReceiptManagerWrapper: _RegistrationCoordinator_ReceiptManagerShim {

    private let manager: OWSReceiptManager
    public init(_ manager: OWSReceiptManager) { self.manager = manager }

    public func setAreReadReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        manager.setAreReadReceiptsEnabled(areEnabled, transaction: tx)
    }

    public func setAreStoryViewedReceiptsEnabled(_ areEnabled: Bool, _ tx: DBWriteTransaction) {
        StoryManager.setAreViewReceiptsEnabled(areEnabled, transaction: tx)
    }
}

// MARK: - StorageService
public protocol _RegistrationCoordinator_StorageServiceManagerShim {
    func rotateManifest(mode: StorageServiceManagerManifestRotationMode, authedDevice: AuthedDevice) async throws
    func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice, masterKeySource: StorageService.MasterKeySource) -> Promise<Void>
    func backupPendingChanges(authedDevice: AuthedDevice)
    func recordPendingLocalAccountUpdates()
}

public class _RegistrationCoordinator_StorageServiceManagerWrapper: _RegistrationCoordinator_StorageServiceManagerShim {
    private let manager: StorageServiceManager
    public init(_ manager: StorageServiceManager) { self.manager = manager }

    public func rotateManifest(
        mode: StorageServiceManagerManifestRotationMode,
        authedDevice: AuthedDevice
    ) async throws {
        try await self.manager.rotateManifest(mode: mode, authedDevice: authedDevice)
    }

    public func restoreOrCreateManifestIfNecessary(
        authedDevice: AuthedDevice,
        masterKeySource: StorageService.MasterKeySource
    ) -> Promise<Void> {
        manager.restoreOrCreateManifestIfNecessary(authedDevice: authedDevice, masterKeySource: masterKeySource)
    }

    public func backupPendingChanges(authedDevice: AuthedDevice) {
        manager.backupPendingChanges(authedDevice: authedDevice)
    }

    public func recordPendingLocalAccountUpdates() {
        manager.recordPendingLocalAccountUpdates()
    }
}

// MARK: - TimeoutProvider

public protocol _RegistrationCoordinator_TimeoutProviderShim {
    var pushTokenMinWaitTime: TimeInterval { get }
    var pushTokenTimeout: TimeInterval { get }
}

public class _RegistrationCoordinator_TimeoutProviderWrapper: _RegistrationCoordinator_TimeoutProviderShim {
    public enum Constants {
        /// How long we wait for a push challenge to the exclusion of all else after requesting one.
        /// Even if we have another challenge to fulfill, we will wait this long before proceeding.
        static let pushTokenMinWaitTime: TimeInterval = 3
        /// How long we block waiting for a push challenge after requesting one.
        /// We might still fulfill the challenge after this, but we won't opportunistically block proceeding.
        static let pushTokenTimeout: TimeInterval = 30
    }

    public var pushTokenMinWaitTime: TimeInterval { Constants.pushTokenMinWaitTime }
    public var pushTokenTimeout: TimeInterval { Constants.pushTokenTimeout }
}

// MARK: - UDManager

public protocol _RegistrationCoordinator_UDManagerShim {

    func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool
}

public class _RegistrationCoordinator_UDManagerWrapper: _RegistrationCoordinator_UDManagerShim {

    private let manager: OWSUDManager
    public init(_ manager: OWSUDManager) { self.manager = manager }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return manager.shouldAllowUnrestrictedAccessLocal(transaction: transaction)
    }
}

// MARK: - UsernameApiClient

public protocol _RegistrationCoordinator_UsernameApiClientShim {
    func confirmReservedUsername(reservedUsername: Usernames.HashedUsername, encryptedUsernameForLink: Data, chatServiceAuth: ChatServiceAuth) async throws -> Usernames.ApiClientConfirmationResult
}

public class _RegistrationCoordinator_UsernameApiClientWrapper: _RegistrationCoordinator_UsernameApiClientShim {

    private let usernameApiClient: any UsernameApiClient
    public init(_ usernameApiClient: any UsernameApiClient) { self.usernameApiClient = usernameApiClient }

    public func confirmReservedUsername(reservedUsername: Usernames.HashedUsername, encryptedUsernameForLink: Data, chatServiceAuth: ChatServiceAuth) async throws -> Usernames.ApiClientConfirmationResult {
        return try await self.usernameApiClient.confirmReservedUsername(reservedUsername: reservedUsername, encryptedUsernameForLink: encryptedUsernameForLink, chatServiceAuth: chatServiceAuth)
    }
}
