//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

fileprivate extension NSNotification.Name {
    /// TODO: remove this notification once bridging between old and new TSAccountManager is done
    /// and no listeners exist.
    static let onboardingStateDidChange: NSNotification.Name = {
        owsAssertDebug(FeatureFlags.tsAccountManagerBridging, "Canary to remove when feature flag is removed")
        return NSNotification.Name("NSNotificationNameOnboardingStateDidChange")
    }()
}

public class RegistrationStateChangeManagerImpl: RegistrationStateChangeManager {

    public typealias TSAccountManager = SignalServiceKit.TSAccountManagerProtocol & LocalIdentifiersSetter

    private let groupsV2: GroupsV2Swift
    private let identityManager: OWSIdentityManager
    private let paymentsEvents: Shims.PaymentsEvents
    private let recipientMerger: RecipientMerger
    private let schedulers: Schedulers
    private let senderKeyStore: Shims.SenderKeyStore
    private let signalProtocolStoreManager: SignalProtocolStoreManager
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager
    private let versionedProfiles: VersionedProfilesSwift

    public init(
        groupsV2: GroupsV2Swift,
        identityManager: OWSIdentityManager,
        paymentsEvents: Shims.PaymentsEvents,
        recipientMerger: RecipientMerger,
        schedulers: Schedulers,
        senderKeyStore: Shims.SenderKeyStore,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager,
        versionedProfiles: VersionedProfilesSwift
    ) {
        self.groupsV2 = groupsV2
        self.identityManager = identityManager
        self.paymentsEvents = paymentsEvents
        self.recipientMerger = recipientMerger
        self.schedulers = schedulers
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
            deviceId: OWSDevice.primaryDeviceId,
            serverAuthToken: authToken,
            tmp_setIsOnboarded: FeatureFlags.tsAccountManagerBridging,
            tx: tx
        )

        didUpdateLocalIdentifiers(e164: e164, aci: aci, pni: pni, tx: tx)

        tx.addAsyncCompletion(on: schedulers.main) {
            self.postLocalNumberDidChangeNotification()
            self.postRegistrationStateDidChangeNotification()
            if FeatureFlags.tsAccountManagerBridging {
                self.tmp_postOnboardingStateDidChangeNotification()
            }
        }
    }

    public func didLinkSecondary(
        e164: E164,
        aci: Aci,
        pni: Pni?,
        authToken: String,
        deviceId: UInt32,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.initializeLocalIdentifiers(
            e164: e164,
            aci: aci,
            pni: pni,
            deviceId: deviceId,
            serverAuthToken: authToken,
            tmp_setIsOnboarded: false,
            tx: tx
        )
        didUpdateLocalIdentifiers(e164: e164, aci: aci, pni: pni, tx: tx)

        tx.addAsyncCompletion(on: schedulers.main) {
            self.postLocalNumberDidChangeNotification()
            self.postRegistrationStateDidChangeNotification()
        }
    }

    public func didFinishProvisioningSecondary(tx: DBWriteTransaction) {
        tsAccountManager.setDidFinishProvisioning(tx: tx)

        tx.addAsyncCompletion(on: schedulers.main) {
            self.postRegistrationStateDidChangeNotification()
        }
    }

    public func didUpdateLocalPhoneNumber(
        _ e164: E164,
        aci: Aci,
        pni: Pni?,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.changeLocalNumber(newE164: e164, aci: aci, pni: pni, tx: tx)

        didUpdateLocalIdentifiers(e164: e164, aci: aci, pni: pni, tx: tx)

        tx.addAsyncCompletion(on: schedulers.main) {
            self.postLocalNumberDidChangeNotification()
        }
    }

    public func resetForReregistration(
        localPhoneNumber: E164,
        localAci: Aci,
        wasPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) -> Bool {
        tsAccountManager.resetForReregistration(localNumber: localPhoneNumber, localAci: localAci, tx: tx)

        signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore.resetSessionStore(tx: tx)
        signalProtocolStoreManager.signalProtocolStore(for: .pni).sessionStore.resetSessionStore(tx: tx)
        senderKeyStore.resetSenderKeyStore(tx: tx)
        udManager.removeSenderCertificates(tx: tx)
        versionedProfiles.clearProfileKeyCredentials(tx: tx)
        groupsV2.clearTemporalCredentials(tx: tx)

        if wasPrimaryDevice {
            // Don't reset payments state at this time.
        } else {
            // PaymentsEvents will dispatch this event to the appropriate singletons.
            paymentsEvents.clearState(tx: tx)
        }

        tx.addAsyncCompletion(on: schedulers.main) {
            self.postRegistrationStateDidChangeNotification()
            self.postLocalNumberDidChangeNotification()
            if FeatureFlags.tsAccountManagerBridging {
                self.tmp_postOnboardingStateDidChangeNotification()
            }
        }

        return true
    }

    public func setIsTransferInProgress(tx: DBWriteTransaction) {
        guard tsAccountManager.setIsTransferInProgress(true, tx: tx) else {
            return
        }
        tx.addAsyncCompletion(on: schedulers.main) {
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
            tx.addAsyncCompletion(on: schedulers.main) {
                self.postRegistrationStateDidChangeNotification()
            }
        }
    }

    public func setWasTransferred(tx: DBWriteTransaction) {
        guard tsAccountManager.setWasTransferred(true, tx: tx) else {
            return
        }
        tx.addAsyncCompletion(on: schedulers.main) {
            self.postRegistrationStateDidChangeNotification()
        }
    }

    // MARK: - Helpers

    private func didUpdateLocalIdentifiers(
        e164: E164,
        aci: Aci,
        pni: Pni?,
        tx: DBWriteTransaction
    ) {
        udManager.removeSenderCertificates(tx: tx)
        identityManager.clearShouldSharePhoneNumberForEveryone(tx: tx)
        versionedProfiles.clearProfileKeyCredentials(tx: tx)
        groupsV2.clearTemporalCredentials(tx: tx)

        storageServiceManager.setLocalIdentifiers(.init(.init(aci: aci, pni: pni, e164: e164)))

        let recipient = recipientMerger.applyMergeForLocalAccount(
            aci: aci,
            phoneNumber: e164,
            pni: pni,
            tx: tx
        )
        // At this stage, the device IDs on the self-recipient are irrelevant (and we always
        // append the primary device id anyway), just use the primary regardless of the local device id.
        recipient.markAsRegisteredAndSave(source: .local, deviceId: OWSDevice.primaryDeviceId, tx: tx)
    }

    // MARK: Notifications

    private func postRegistrationStateDidChangeNotification() {
        NotificationCenter.default.postNotificationNameAsync(
            .registrationStateDidChange,
            object: nil
        )
    }

    private func postLocalNumberDidChangeNotification() {
        NotificationCenter.default.postNotificationNameAsync(
            .localNumberDidChange,
            object: nil
        )
    }

    private func tmp_postOnboardingStateDidChangeNotification() {
        guard FeatureFlags.tsAccountManagerBridging else {
            return
        }
        NotificationCenter.default.postNotificationNameAsync(
            .onboardingStateDidChange,
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
