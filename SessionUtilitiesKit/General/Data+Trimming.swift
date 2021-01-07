
public extension Data {

    func removing05PrefixIfNeeded() -> Data {
        var result = self
        if result.count == 33 && result.toHexString().hasPrefix("05") { result.removeFirst() }
        return result
    }
}

@objc public extension NSData {
    
    @objc func removing05PrefixIfNeeded() -> NSData {
        var result = self as Data
        if result.count == 33 && result.toHexString().hasPrefix("05") { result.removeFirst() }
        return result as NSData
    }
}
