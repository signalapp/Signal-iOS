// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Dictionary {
    
    var prettifiedDescription: String {
        return "[ " + map { key, value in
            let keyDescription = String(describing: key)
            let valueDescription = String(describing: value)
            let maxLength = 20
            let truncatedValueDescription = valueDescription.count > maxLength ? valueDescription.prefix(maxLength) + "..." : valueDescription
            return keyDescription + " : " + truncatedValueDescription
        }.joined(separator: ", ") + " ]"
    }
    
    func asArray() -> [(key: Key, value: Value)] {
        return Array(self)
    }
}

public extension Dictionary.Values {
    func asArray() -> [Value] {
        return Array(self)
    }
}

// MARK: - Functional Convenience

public extension Dictionary {
    subscript(_ key: Key?) -> Value? {
        guard let key: Key = key else { return nil }
        
        return self[key]
    }
    
    func setting(_ key: Key?, _ value: Value?) -> [Key: Value] {
        guard let key: Key = key else { return self }
        
        var updatedDictionary: [Key: Value] = self
        updatedDictionary[key] = value

        return updatedDictionary
    }
    
    func updated(with other: [Key: Value]) -> [Key: Value] {
        var updatedDictionary: [Key: Value] = self
        
        other.forEach { key, value in
            updatedDictionary[key] = value
        }

        return updatedDictionary
    }
    
    func removingValue(forKey key: Key?) -> [Key: Value] {
        guard let key: Key = key else { return self }
        
        var updatedDictionary: [Key: Value] = self
        updatedDictionary.removeValue(forKey: key)

        return updatedDictionary
    }
}
