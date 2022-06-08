// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Data {

    func removingIdPrefixIfNeeded() -> Data {
        var result = self
        if result.count == 33 && SessionId.Prefix(from: result.toHexString()) != nil { result.removeFirst() }
        return result
    }
    
    func appending(_ other: Data) -> Data {
        var mutableData: Data = Data()
        mutableData.append(self)
        mutableData.append(other)
        
        return mutableData
    }
    
    func appending(_ other: [UInt8]) -> Data {
        var mutableData: Data = Data()
        mutableData.append(self)
        mutableData.append(contentsOf: other)
        
        return mutableData
    }
}

@objc public extension NSData {
    
    @objc func removingIdPrefixIfNeeded() -> NSData {
        var result = self as Data
        if result.count == 33 && SessionId.Prefix(from: result.toHexString()) != nil { result.removeFirst() }
        return result as NSData
    }
}
