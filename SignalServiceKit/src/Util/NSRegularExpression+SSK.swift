//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension NSRegularExpression {

    @objc
    public func hasMatch(input: String) -> Bool {
        return self.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) != nil
    }
}
