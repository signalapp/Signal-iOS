
public extension String {

    func removing05PrefixIfNeeded() -> String {
        var result = self
        if result.count == 66 && result.hasPrefix("05") { result.removeFirst(2) }
        return result
    }
}

@objc public extension NSString {
    
    @objc func removing05PrefixIfNeeded() -> NSString {
        var result = self as String
        if result.count == 66 && result.hasPrefix("05") { result.removeFirst(2) }
        return result as NSString
    }
}
