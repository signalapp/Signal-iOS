
public extension String {

    func removingIdPrefixIfNeeded() -> String {
        var result = self
        if result.count == 66 && SessionId.Prefix(from: result) != nil { result.removeFirst(2) }
        return result
    }
}

@objc public extension NSString {
    
    @objc func removingIdPrefixIfNeeded() -> NSString {
        var result = self as String
        if result.count == 66 && SessionId.Prefix(from: result) != nil { result.removeFirst(2) }
        return result as NSString
    }
}
