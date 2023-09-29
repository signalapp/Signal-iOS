//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol NotificationsProtocolSwift: NotificationsProtocol {

    func notifyUserOfDeregistration(tx: DBWriteTransaction)
}
