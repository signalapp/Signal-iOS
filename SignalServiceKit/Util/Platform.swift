//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class Platform: NSObject {

    @objc
    public static let isSimulator: Bool = {
        let isSim: Bool
        #if targetEnvironment(simulator)
            isSim = true
        #else
            isSim = false
        #endif
        return isSim
    }()
}
