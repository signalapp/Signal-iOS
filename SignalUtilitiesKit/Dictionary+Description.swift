
public extension Dictionary {
    
    public var prettifiedDescription: String {
        return "[ " + map { key, value in
            let keyDescription = String(describing: key)
            let valueDescription = String(describing: value)
            let maxLength = 20
            let truncatedValueDescription = valueDescription.count > maxLength ? valueDescription.prefix(maxLength) + "..." : valueDescription
            return keyDescription + " : " + truncatedValueDescription
        }.joined(separator: ", ") + " ]"
    }
}
