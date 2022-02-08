
public extension Data {

    func removingIdPrefixIfNeeded() -> Data {
        var result = self
        if result.count == 33 && IdPrefix(with: result.toHexString()) != nil { result.removeFirst() }
        return result
    }
}

@objc public extension NSData {
    
    @objc func removingIdPrefixIfNeeded() -> NSData {
        var result = self as Data
        if result.count == 33 && IdPrefix(with: result.toHexString()) != nil { result.removeFirst() }
        return result as NSData
    }
}
