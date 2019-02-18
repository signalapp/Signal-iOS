//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension String {
    public var digitsOnly: String {
        return (self as NSString).digitsOnly()
    }

    func rtlSafeAppend(_ string: String) -> String {
        return (self as NSString).rtlSafeAppend(string)
    }

    public func substring(from index: Int) -> String {
        return String(self[self.index(self.startIndex, offsetBy: index)...])
    }

    public func substring(to index: Int) -> String {
        return String(prefix(index))
    }
}
