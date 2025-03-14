//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class TSAccountManagerObjcBridge: NSObject {

    public static var isRegisteredWithMaybeTransaction: Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
    }

    public static var isPrimaryDeviceWithMaybeTransaction: Bool {
        return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true
    }

    @objc
    public static func localAciAddress(with tx: DBReadTransaction) -> SignalServiceAddress? {
        return DependenciesBridge.shared.tsAccountManager
            .localIdentifiers(tx: tx)?
            .aciAddress
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
