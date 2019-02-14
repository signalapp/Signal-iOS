//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension String {
    func rtlSafeAppend(_ string: String) -> String {
        return (self as NSString).rtlSafeAppend(string)
    }

    public func substring(from index: Int) -> String {
        return String(self[self.index(self.startIndex, offsetBy: index)...])
    }
}
