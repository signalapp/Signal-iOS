//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension NSNotification.Name {
    static let registrationStateDidChange = NSNotification.Name("NSNotificationNameRegistrationStateDidChange")
    static let localNumberDidChange = NSNotification.Name("NSNotificationNameLocalNumberDidChange")
}

// TODO: rename to TSAccountManager after removing the original
public protocol TSAccountManagerProtocol {

    func warmCaches()

    // MARK: - Local Identifiers

    var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { get }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers?

    // MARK: - Registration State

    var registrationStateWithMaybeSneakyTransaction: TSRegistrationState { get }

    func registrationState(tx: DBReadTransaction) -> TSRegistrationState

    // MARK: - RegistrationIds

    func getOrGenerateAciRegistrationId(tx: DBWriteTransaction) -> UInt32
    func getOrGeneratePniRegistrationId(tx: DBWriteTransaction) -> UInt32

    // MARK: - Manual Message Fetch

    func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool
    func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction)

    // MARK: - Phone Number Discoverability

    func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool
    func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool
}

/// Should only be used in ``PhoneNumberDiscoverabilityManager``, so that necessary
/// side effects can be triggered.
public protocol PhoneNumberDiscoverabilitySetter {

    func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, tx: DBWriteTransaction)
}
