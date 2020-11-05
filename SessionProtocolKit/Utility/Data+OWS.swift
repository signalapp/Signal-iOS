//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

extension Data {
    public var hexadecimalString: String {
        return (self as NSData).hexadecimalString()
    }
    
    public static func data(fromHex hexString: String) -> Data? {
        guard let data = NSData(fromHexString : hexString) else {
            return nil
        }
        return data as Data
    }

    public func ows_constantTimeIsEqual(to other: Data) -> Bool {
        return (self as NSData).ows_constantTimeIsEqual(to: other)
    }
}
