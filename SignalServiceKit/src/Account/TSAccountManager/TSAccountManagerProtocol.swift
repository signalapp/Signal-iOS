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

    var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { get }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers?
}
