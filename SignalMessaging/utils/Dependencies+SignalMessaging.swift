//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// MARK: - NSObject

@objc
public extension NSObject {

    var lightweightGroupCallManager: LightweightGroupCallManager? {
        SMEnvironment.shared.lightweightGroupCallManagerRef
    }

    static var lightweightGroupCallManager: LightweightGroupCallManager? {
        SMEnvironment.shared.lightweightGroupCallManagerRef
    }
}
