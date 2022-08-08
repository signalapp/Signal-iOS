// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SignalCoreKit

public extension OWSAES256Key {
    convenience init?(data: Data?) {
        guard let existingData: Data = data else { return nil }
        
        self.init(data: existingData)
    }
}
