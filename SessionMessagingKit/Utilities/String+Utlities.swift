// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

internal extension String {
    func appending(_ other: String?) -> String {
        guard let value: String = other else { return self }
        
        return self.appending(value)
    }
}
