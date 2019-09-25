
public extension String {
    
    public func removing05PrefixIfNeeded() -> String {
        var result = self
        if result.count == 66 && result.hasPrefix("05") { result.removeFirst(2) }
        return result
    }
    
    public func adding05PrefixIfNeeded() -> String {
        if count == 64 {
            return "05" + self
        } else {
            return self
        }
    }
}
