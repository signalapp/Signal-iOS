//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class RegistrationStateChangeManagerImpl: RegistrationStateChangeManager {

    public typealias TSAccountManager = SignalServiceKit.TSAccountManager & LocalIdentifiersSetter

    private let accountKeyStore: AccountKeyStore
    private let appContext: AppContext
    private let authCredentialStore: AuthCredentialStore
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupCDNCredentialStore: BackupCDNCredentialStore
    private let backupKeyService: BackupKeyService
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    private var chatConnectionManager: any ChatConnectionManager {
        // TODO: Fix circular dependency.
        return DependenciesBridge.shared.chatConnectionManager
    }
    private let db: DB
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let identityManager: OWSIdentityManager
    private let networkManager: NetworkManager
    private let notificationPresenter: any NotificationPresenter
    private let paymentsEvents: Shims.PaymentsEvents
    private let recipientManager: any SignalRecipientManager
    private let recipientMerger: RecipientMerger
    private let senderKeyStore: Shims.SenderKeyStore
    private let signalProtocolStoreManager: SignalProtocolStoreManager
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager
    private let versionedProfiles: VersionedProfiles

    init(
        accountKeyStore: AccountKeyStore,
        appContext: AppContext,
        authCredentialStore: AuthCredentialStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupCDNCredentialStore: BackupCDNCredentialStore,
        backupKeyService: BackupKeyService,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager,
        db: DB,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        identityManager: OWSIdentityManager,
        networkManager: NetworkManager,
        notificationPresenter: any NotificationPresenter,
        paymentsEvents: Shims.PaymentsEvents,
        recipientManager: any SignalRecipientManager,
        recipientMerger: RecipientMerger,
        senderKeyStore: Shims.SenderKeyStore,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager,
        versionedProfiles: VersionedProfiles
    ) {
        self.accountKeyStore = accountKeyStore
        self.appContext = appContext
        self.authCredentialStore = authCredentialStore
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupCDNCredentialStore = backupCDNCredentialStore
        self.backupKeyService = backupKeyService
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.backupTestFlightEntitlementManager = backupTestFlightEntitlementManager
        self.db = db
        self.dmConfigurationStore = dmConfigurationStore
        self.groupsV2 = groupsV2
        self.identityManager = identityManager
        self.networkManager = networkManager
        self.notificationPresenter = notificationPresenter
        self.paymentsEvents = paymentsEvents
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.senderKeyStore = senderKeyStore
        self.signalProtocolStoreManager = signalProtocolStoreManager
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
        self.versionedProfiles = versionedProfiles
    }

    public func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return tsAccountManager.registrationState(tx: tx)
    }

    public func didRegisterPrimary(
        e164: E164,
        aci: Aci,
        pni: Pni,
        authToken: String,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.initializeLocalIdentifiers(
            e164: e164,
            aci: aci,
            pni: pni,
            deviceId: .primary,
            serverAuthToken: authToken,
            tx: tx
        )

        didUpdateLocalIdentifiers(e164: e164, aci: aci, pni: pni, deviceId: .primary, tx: tx)

        tx.addSyncCompletion {
            self.postLocalNumberDidChangeNotification()
            self.postRegistrationStateDidChangeNotification()
        }
    }

    public func didProvisionSecondary(
        e164: E164,
        aci: Aci,
        pni: Pni,
        authToken: String,
        deviceId: DeviceId,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.initializeLocalIdentifiers(
            e164: e164,
            aci: aci,
            pni: pni,
            deviceId: deviceId,
            serverAuthToken: authToken,
            tx: tx
        )
        didUpdateLocalIdentifiers(e164: e164, aci: aci, pni: pni, deviceId: deviceId, tx: tx)

        tx.addSyncCompletion {
            self.postLocalNumberDidChangeNotification()
            self.postRegistrationStateDidChangeNotification()
        }
    }

    public func didUpdateLocalPhoneNumber(
        _ e164: E164,
        aci: Aci,
        pni: Pni,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.changeLocalNumber(newE164: e164, aci: aci, pni: pni, tx: tx)

        didUpdateLocalIdentifiers(e164: e164, aci: aci, pni: pni, deviceId: .primary, tx: tx)

        tx.addSyncCompletion {
            self.postLocalNumberDidChangeNotification()
        }
    }

    public func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) {
        let didChange = tsAccountManager.setIsDeregisteredOrDelinked(isDeregisteredOrDelinked, tx: tx)
        guard didChange else {
            return
        }
        Logger.warn("Updating isDeregisteredOrDelinked \(isDeregisteredOrDelinked)")

        if isDeregisteredOrDelinked {
            if self.isUnregisteringFromService.get() {
                Logger.warn("Skipping notification because we're unregistering ourselves.")
            } else {
                notificationPresenter.notifyUserOfDeregistration(tx: tx)
            }

            // Rotate the upload era, thereby ensuring that when we reregister
            // we will run a list-media.
            backupAttachmentUploadEraStore.rotateUploadEra(tx: tx)

            // Wipe our cached Backup credentials, which may be invalid if we
            // eventually re-register.
            authCredentialStore.removeAllBackupAuthCredentials(tx: tx)
            backupCDNCredentialStore.wipe(tx: tx)

            // A registration event that caused us to become deregistered will
            // have wiped our server-side Backup entitlement, so we should make
            // sure that if we ever become registered again we attempt to get
            // said entitlement again immediately.
            backupSubscriptionManager.setRedemptionAttemptIsNecessary(tx: tx)
            backupTestFlightEntitlementManager.setRenewEntitlementIsNecessary(tx: tx)

            // On linked devices, reset all DM timer versions. If the user
            // relinks a new primary and resets all its DM timer versions,
            // our local higher version number would prevent us getting
            // back in sync. So we pre-emptively reset too. If we relink
            // to a primary that preserves versions we'll catch back
            // up via contact sync.
            switch tsAccountManager.registrationState(tx: tx) {
            case .delinked:
                do {
                    try dmConfigurationStore.resetAllDMTimerVersions(tx: tx)
                } catch {
                    owsFailDebug("Failed to reset dm timer versions \(error.grdbErrorForLogging)")
                }
            default:
                break
            }
        }
        postRegistrationStateDidChangeNotification()
    }

    public func resetForReregistration(
        localPhoneNumber: E164,
        localAci: Aci,
        discoverability: PhoneNumberDiscoverability?,
        wasPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.resetForReregistration(
            localNumber: localPhoneNumber,
            localAci: localAci,
            discoverability: discoverability,
            wasPrimaryDevice: wasPrimaryDevice,
            tx: tx
        )

        signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore.resetSessionStore(tx: tx)
        signalProtocolStoreManager.signalProtocolStore(for: .pni).sessionStore.resetSessionStore(tx: tx)
        senderKeyStore.resetSenderKeyStore(tx: tx)
        udManager.removeSenderCertificates(tx: tx)
        versionedProfiles.clearProfileKeyCredentials(tx: tx)
        authCredentialStore.removeAllGroupAuthCredentials(tx: tx)
        authCredentialStore.removeAllCallLinkAuthCredentials(tx: tx)

        if wasPrimaryDevice {
            // Don't reset payments state at this time.
        } else {
            // PaymentsEvents will dispatch this event to the appropriate singletons.
            paymentsEvents.clearState(tx: tx)
        }

        tx.addSyncCompletion {
            self.postRegistrationStateDidChangeNotification()
            self.postLocalNumberDidChangeNotification()
        }
    }

    public func setIsTransferInProgress(tx: DBWriteTransaction) {
        guard tsAccountManager.setIsTransferInProgress(true, tx: tx) else {
            return
        }
        tx.addSyncCompletion {
            self.postRegistrationStateDidChangeNotification()
        }
    }

    public func setIsTransferComplete(
        sendStateUpdateNotification: Bool,
        tx: DBWriteTransaction
    ) {
        guard tsAccountManager.setIsTransferInProgress(false, tx: tx) else {
            return
        }
        if sendStateUpdateNotification {
            tx.addSyncCompletion {
                self.postRegistrationStateDidChangeNotification()
            }
        }
    }

    public func setWasTransferred(tx: DBWriteTransaction) {
        guard tsAccountManager.setWasTransferred(true, tx: tx) else {
            return
        }
        tx.addSyncCompletion {
            self.postRegistrationStateDidChangeNotification()
        }
    }

    public func cleanUpTransferStateOnAppLaunchIfNeeded() {
        tsAccountManager.cleanUpTransferStateOnAppLaunchIfNeeded()
    }

    private let isUnregisteringFromService = AtomicValue(false, lock: .init())

    public func unregisterFromService() async throws -> Never {
        owsAssertBeta(appContext.isMainAppAndActive)

        let (localIdentifiers, messageBackupKey, mediaBackupKey) = db.read { tx in
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
            var messageBackupKey: MessageRootBackupKey?
            if let aci = localIdentifiers?.aci {
                messageBackupKey = try? accountKeyStore.getMessageRootBackupKey(aci: aci, tx: tx)
            }
            return (
                localIdentifiers,
                messageBackupKey,
                accountKeyStore.getMediaRootBackupKey(tx: tx)
            )
        }

        // Fetch Backup auth before unregistering ourselves remotely, for use
        // after we make the unregistration request.
        let backupAuths: [BackupServiceAuth]?
        if let localIdentifiers {
            backupAuths = await withTaskGroup { [backupRequestManager] taskGroup in
                for credentialType in BackupAuthCredentialType.allCases {
                    let backupKey: BackupKeyMaterial? = switch credentialType {
                    case .messages: messageBackupKey
                    case .media: mediaBackupKey
                    }
                    if let backupKey {
                        taskGroup.addTask {
                            return try? await backupRequestManager.fetchBackupServiceAuth(
                                for: backupKey,
                                localAci: localIdentifiers.aci,
                                auth: .implicit()
                            )
                        }
                    }
                }

                var auths: [BackupServiceAuth] = []
                for await auth in taskGroup {
                    guard let auth else { continue }
                    auths.append(auth)
                }
                return auths
            }
        } else {
            backupAuths = nil
        }

        try await deleteLocalDevice(OWSRequestFactory.unregisterAccountRequest(), canUseWebSocket: true)

        // Now that we've successfully unregistered, make a best effort to wipe
        // our Backups. This is safe to try even if Backups were disabled.
        if let localIdentifiers, let backupAuths {
            for backupAuth in backupAuths {
                try? await Retry.performWithBackoff(
                    maxAttempts: 3,
                    isRetryable: { $0.isNetworkFailureOrTimeout || ($0 as? OWSHTTPError)?.isRetryable == true },
                    block: {
                        try await backupKeyService.deleteBackupKey(
                            localIdentifiers: localIdentifiers,
                            backupAuth: backupAuth
                        )
                    }
                )
            }
        }
        // No need to set any state, as we wipe the whole app anyway.

        await appContext.resetAppDataAndExit()
    }

    public func unlinkLocalDevice(localDeviceId: LocalDeviceId, auth: ChatServiceAuth) async throws {
        owsPrecondition(!localDeviceId.equals(.primary))
        if let localDeviceId = localDeviceId.ifValid {
            var request = TSRequest.deleteDevice(deviceId: localDeviceId)
            request.auth = .identified(auth)
            try await deleteLocalDevice(request, canUseWebSocket: FeatureFlags.postRegWebSocket)
        } else {
            // If localDeviceId isn't valid, we've already been unlinked.
        }
    }

    private func deleteLocalDevice(_ request: TSRequest, canUseWebSocket: Bool) async throws {
        self.isUnregisteringFromService.set(true)
        defer { self.isUnregisteringFromService.set(false) }

        do {
            _ = try await networkManager.asyncRequest(request, canUseWebSocket: canUseWebSocket)
        } catch OWSHTTPError.networkFailure(.wrappedFailure(SignalError.connectionInvalidated)) {
            Logger.warn("Connection was invalidated -- we this device (or account) was probably deleted.")
            // The server closed the connection before we got a response. This almost
            // certainly happened because this device is no longer registered, but
            // `connectionInvalidated` may happen for other reasons. This is (sort of)
            // a "flaky" failure, so we retry the request. We expect to receive a
            // NotRegisteredError (via a 403 when reopening the socket), but if we
            // don't, we throw whatever error happens on the second attempt.
            do {
                _ = try await networkManager.asyncRequest(request, canUseWebSocket: canUseWebSocket)
            } catch is NotRegisteredError {
                // This is expected when the `connectionInvalidated` error races the
                // response to the INITIAL request.
            }
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
            throw error
        }

        // If we successfully delete this device, the connection will close and
        // stop trying to reopen. Wait until that happens to ensure we don't post a
        // notification about being deregistered.
        try await chatConnectionManager.waitUntilIdentifiedConnectionShouldBeClosed()
    }

    // MARK: - Helpers

    private func didUpdateLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni,
        deviceId: DeviceId,
        tx: DBWriteTransaction
    ) {
        udManager.removeSenderCertificates(tx: tx)
        identityManager.clearShouldSharePhoneNumberForEveryone(tx: tx)
        versionedProfiles.clearProfileKeyCredentials(tx: tx)
        authCredentialStore.removeAllGroupAuthCredentials(tx: tx)
        authCredentialStore.removeAllCallLinkAuthCredentials(tx: tx)

        storageServiceManager.setLocalIdentifiers(LocalIdentifiers(aci: aci, pni: pni, e164: e164))

        let recipient = recipientMerger.applyMergeForLocalAccount(
            aci: aci,
            phoneNumber: e164,
            pni: pni,
            tx: tx
        )
        // Always add the .primary DeviceId as well as our own. This is how linked
        // devices know to send their initial sync messages to the primary.
        recipientManager.modifyAndSave(
            recipient,
            deviceIdsToAdd: [deviceId, .primary],
            deviceIdsToRemove: [],
            shouldUpdateStorageService: false,
            tx: tx
        )
    }

    // MARK: Notifications

    private func postRegistrationStateDidChangeNotification() {
        NotificationCenter.default.postOnMainThread(
            name: .registrationStateDidChange,
            object: nil
        )
    }

    private func postLocalNumberDidChangeNotification() {
        NotificationCenter.default.postOnMainThread(
            name: .localNumberDidChange,
            object: nil
        )
    }
}

// MARK: - Shims

extension RegistrationStateChangeManagerImpl {
    public enum Shims {
        public typealias PaymentsEvents = _RegistrationStateChangeManagerImpl_PaymentsEventsShim
        public typealias SenderKeyStore = _RegistrationStateChangeManagerImpl_SenderKeyStoreShim
    }

    public enum Wrappers {
        public typealias PaymentsEvents = _RegistrationStateChangeManagerImpl_PaymentsEventsWrapper
        public typealias SenderKeyStore = _RegistrationStateChangeManagerImpl_SenderKeyStoreWrapper
    }
}

// MARK: PaymentsEvents

public protocol _RegistrationStateChangeManagerImpl_PaymentsEventsShim {

    func clearState(tx: DBWriteTransaction)
}

public class _RegistrationStateChangeManagerImpl_PaymentsEventsWrapper: _RegistrationStateChangeManagerImpl_PaymentsEventsShim {

    private let paymentsEvents: PaymentsEvents

    public init(_ paymentsEvents: PaymentsEvents) {
        self.paymentsEvents = paymentsEvents
    }

    public func clearState(tx: DBWriteTransaction) {
        paymentsEvents.clearState(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: SenderKeyStore

public protocol _RegistrationStateChangeManagerImpl_SenderKeyStoreShim {

    func resetSenderKeyStore(tx: DBWriteTransaction)
}

public class _RegistrationStateChangeManagerImpl_SenderKeyStoreWrapper: _RegistrationStateChangeManagerImpl_SenderKeyStoreShim {

    private let senderKeyStore: SenderKeyStore

    public init(_ senderKeyStore: SenderKeyStore) {
        self.senderKeyStore = senderKeyStore
    }

    public func resetSenderKeyStore(tx: DBWriteTransaction) {
        senderKeyStore.resetSenderKeyStore(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

extension RegistrationStateChangeManagerImpl {

    public func registerForTests(
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        owsAssertDebug(CurrentAppContext().isRunningTests)

        tsAccountManager.initializeLocalIdentifiers(
            e164: E164(localIdentifiers.phoneNumber)!,
            aci: localIdentifiers.aci,
            pni: localIdentifiers.pni!,
            deviceId: .primary,
            serverAuthToken: "",
            tx: tx
        )
        didUpdateLocalIdentifiers(
            e164: E164(localIdentifiers.phoneNumber)!,
            aci: localIdentifiers.aci,
            pni: localIdentifiers.pni!,
            deviceId: .primary,
            tx: tx
        )
    }
}

#endif
