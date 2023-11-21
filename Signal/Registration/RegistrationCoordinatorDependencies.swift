//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public struct RegistrationCoordinatorDependencies {
    public let appExpiry: AppExpiry
    public let changeNumberPniManager: ChangePhoneNumberPniManager
    public let contactsManager: RegistrationCoordinatorImpl.Shims.ContactsManager
    public let contactsStore: RegistrationCoordinatorImpl.Shims.ContactsStore
    public let dateProvider: DateProvider
    public let db: DB
    public let experienceManager: RegistrationCoordinatorImpl.Shims.ExperienceManager
    public let keyValueStoreFactory: KeyValueStoreFactory
    public let messagePipelineSupervisor: RegistrationCoordinatorImpl.Shims.MessagePipelineSupervisor
    public let messageProcessor: RegistrationCoordinatorImpl.Shims.MessageProcessor
    public let ows2FAManager: RegistrationCoordinatorImpl.Shims.OWS2FAManager
    public let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    public let preKeyManager: PreKeyManager
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

    public static func from(_ object: NSObject) -> RegistrationCoordinatorDependencies {
        return RegistrationCoordinatorDependencies(
            appExpiry: DependenciesBridge.shared.appExpiry,
            changeNumberPniManager: DependenciesBridge.shared.changePhoneNumberPniManager,
            contactsManager: RegistrationCoordinatorImpl.Wrappers.ContactsManager(object.contactsManagerImpl),
            contactsStore: RegistrationCoordinatorImpl.Wrappers.ContactsStore(),
            dateProvider: { Date() },
            db: DependenciesBridge.shared.db,
            experienceManager: RegistrationCoordinatorImpl.Wrappers.ExperienceManager(),
            keyValueStoreFactory: DependenciesBridge.shared.keyValueStoreFactory,
            messagePipelineSupervisor: RegistrationCoordinatorImpl.Wrappers.MessagePipelineSupervisor(object.messagePipelineSupervisor),
            messageProcessor: RegistrationCoordinatorImpl.Wrappers.MessageProcessor(object.messageProcessor),
            ows2FAManager: RegistrationCoordinatorImpl.Wrappers.OWS2FAManager(object.ows2FAManager),
            phoneNumberDiscoverabilityManager: DependenciesBridge.shared.phoneNumberDiscoverabilityManager,
            preKeyManager: DependenciesBridge.shared.preKeyManager,
            profileManager: RegistrationCoordinatorImpl.Wrappers.ProfileManager(object.profileManager),
            pushRegistrationManager: RegistrationCoordinatorImpl.Wrappers.PushRegistrationManager(object.pushRegistrationManager),
            receiptManager: RegistrationCoordinatorImpl.Wrappers.ReceiptManager(object.receiptManager),
            registrationStateChangeManager: DependenciesBridge.shared.registrationStateChangeManager,
            schedulers: DependenciesBridge.shared.schedulers,
            sessionManager: DependenciesBridge.shared.registrationSessionManager,
            signalService: object.signalService,
            storageServiceManager: object.storageServiceManager,
            svr: DependenciesBridge.shared.svr,
            svrAuthCredentialStore: DependenciesBridge.shared.svrCredentialStorage,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            udManager: RegistrationCoordinatorImpl.Wrappers.UDManager(object.udManager)
        )
    }
}
