//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
@objcMembers
public class TSAccountManagerObjcBridge: NSObject {

    private override init() { super.init() }

    public static var isRegisteredWithMaybeTransaction: Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
    }

    public static func isRegistered(with tx: SDSAnyReadTransaction) -> Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isRegistered
    }

    public static var isRegisteredPrimaryDeviceWithMaybeTransaction: Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice
    }

    public static var isPrimaryDeviceWithMaybeTransaction: Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true
    }

    public static func isPrimaryDevice(with tx: SDSAnyReadTransaction) -> Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice ?? true
    }

    public static var localIdentifiersWithMaybeTransaction: LocalIdentifiersObjC? {
        return DependenciesBridge.shared.tsAccountManager
            .localIdentifiersWithMaybeSneakyTransaction
            .map(LocalIdentifiersObjC.init)
    }

    public static func localIdentifiers(with tx: SDSAnyReadTransaction) -> LocalIdentifiersObjC? {
        return DependenciesBridge.shared.tsAccountManager
            .localIdentifiers(tx: tx.asV2Read)
            .map(LocalIdentifiersObjC.init)
    }

    public static var localAciAddressWithMaybeTransaction: SignalServiceAddress? {
        return DependenciesBridge.shared.tsAccountManager
            .localIdentifiersWithMaybeSneakyTransaction?
            .aciAddress
    }

    public static func localAciAddress(with tx: SDSAnyReadTransaction) -> SignalServiceAddress? {
        return DependenciesBridge.shared.tsAccountManager
            .localIdentifiers(tx: tx.asV2Read)?
            .aciAddress
    }

    public static var storedDeviceIdWithMaybeTransaction: UInt32 {
        return DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction
    }

    public static func storedDeviceId(with tx: SDSAnyReadTransaction) -> UInt32 {
        return DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx.asV2Read)
    }

    public static var isTransferInProgressWithMaybeTransaction: Bool {
        switch DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .transferringIncoming, .transferringLinkedOutgoing, .transferringPrimaryOutgoing:
            return true
        default:
            return false
        }
    }
}
