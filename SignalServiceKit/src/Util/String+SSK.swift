//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension String {
    func rtlSafeAppend(_ string: String) -> String {
        return (self as NSString).rtlSafeAppend(string)
    }
}
