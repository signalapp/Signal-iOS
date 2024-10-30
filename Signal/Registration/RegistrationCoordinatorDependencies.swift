//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public struct RegistrationCoordinatorDependencies {
    public let appExpiry: AppExpiry
    public let changeNumberPniManager: ChangePhoneNumberPniManager
    public let contactsManager: RegistrationCoordinatorImpl.Shims.ContactsManager
    public let contactsStore: RegistrationCoordinatorImpl.Shims.ContactsStore
    public let dateProvider: DateProvider
    public let db: any DB
    public let experienceManager: RegistrationCoordinatorImpl.Shims.ExperienceManager
    public let featureFlags: RegistrationCoordinatorImpl.Shims.FeatureFlags
    public let keyValueStoreFactory: KeyValueStoreFactory
    public let localUsernameManager: LocalUsernameManager
    public let messageBackupErrorPresenter: MessageBackupErrorPresenter
    public let messageBackupManager: MessageBackupManager
    public let messagePipelineSupervisor: RegistrationCoordinatorImpl.Shims.MessagePipelineSupervisor
    public let messageProcessor: RegistrationCoordinatorImpl.Shims.MessageProcessor
    public let ows2FAManager: RegistrationCoordinatorImpl.Shims.OWS2FAManager
    public let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    public let preKeyManager: RegistrationCoordinatorImpl.Shims.PreKeyManager
    public let profileManager: RegistrationCoordinatorImpl.Shims.ProfileManager
    public let pushRegistrationManager: RegistrationCoordinatorImpl.Shims.PushRegistrationManager
    public let receiptManager: RegistrationCoordinatorImpl.Shims.ReceiptManager
    public let registrationStateChangeManager: RegistrationStateChangeManager
    public let schedulers: Schedulers
    public let sessionManager: RegistrationSessionManager
    public let signalService: OWSSignalServiceProtocol
    public let storageServiceManager: StorageServiceManager
    public let svr: SecureValueRecovery
    public let svrAuthCredentialStore: SVRAuthCredentialStorage
    public let tsAccountManager: TSAccountManager
    public let udManager: RegistrationCoordinatorImpl.Shims.UDManager
    public let usernameApiClient: UsernameApiClient
    public let usernameLinkManager: UsernameLinkManager

    public static func from(_ object: NSObject) -> RegistrationCoordinatorDependencies {
        return RegistrationCoordinatorDependencies(
            appExpiry: DependenciesBridge.shared.appExpiry,
            changeNumberPniManager: DependenciesBridge.shared.changePhoneNumberPniManager,
            contactsManager: RegistrationCoordinatorImpl.Wrappers.ContactsManager(SSKEnvironment.shared.contactManagerImplRef),
            contactsStore: RegistrationCoordinatorImpl.Wrappers.ContactsStore(),
            dateProvider: { Date() },
            db: DependenciesBridge.shared.db,
            experienceManager: RegistrationCoordinatorImpl.Wrappers.ExperienceManager(),
            featureFlags: RegistrationCoordinatorImpl.Wrappers.FeatureFlags(),
            keyValueStoreFactory: DependenciesBridge.shared.keyValueStoreFactory,
            localUsernameManager: DependenciesBridge.shared.localUsernameManager,
            messageBackupErrorPresenter: DependenciesBridge.shared.messageBackupErrorPresenter,
            messageBackupManager: DependenciesBridge.shared.messageBackupManager,
            messagePipelineSupervisor: RegistrationCoordinatorImpl.Wrappers.MessagePipelineSupervisor(SSKEnvironment.shared.messagePipelineSupervisorRef),
            messageProcessor: RegistrationCoordinatorImpl.Wrappers.MessageProcessor(SSKEnvironment.shared.messageProcessorRef),
            ows2FAManager: RegistrationCoordinatorImpl.Wrappers.OWS2FAManager(SSKEnvironment.shared.ows2FAManagerRef),
            phoneNumberDiscoverabilityManager: DependenciesBridge.shared.phoneNumberDiscoverabilityManager,
            preKeyManager: RegistrationCoordinatorImpl.Wrappers.PreKeyManager(
                DependenciesBridge.shared.preKeyManager
            ),
            profileManager: RegistrationCoordinatorImpl.Wrappers.ProfileManager(SSKEnvironment.shared.profileManagerRef),
            pushRegistrationManager: RegistrationCoordinatorImpl.Wrappers.PushRegistrationManager(AppEnvironment.shared.pushRegistrationManagerRef),
            receiptManager: RegistrationCoordinatorImpl.Wrappers.ReceiptManager(SSKEnvironment.shared.receiptManagerRef),
            registrationStateChangeManager: DependenciesBridge.shared.registrationStateChangeManager,
            schedulers: DependenciesBridge.shared.schedulers,
            sessionManager: DependenciesBridge.shared.registrationSessionManager,
            signalService: SSKEnvironment.shared.signalServiceRef,
            storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef,
            svr: DependenciesBridge.shared.svr,
            svrAuthCredentialStore: DependenciesBridge.shared.svrCredentialStorage,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            udManager: RegistrationCoordinatorImpl.Wrappers.UDManager(SSKEnvironment.shared.udManagerRef),
            usernameApiClient: DependenciesBridge.shared.usernameApiClient,
            usernameLinkManager: DependenciesBridge.shared.usernameLinkManager
        )
    }
}
