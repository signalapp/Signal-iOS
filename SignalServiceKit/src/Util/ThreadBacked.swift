//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// Thread local
@propertyWrapper
public struct ThreadBacked<Value> {
    private let key: String
    private let defaultValue: Value
    
    public init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }
    
    public var wrappedValue: Value {
        get {
            guard let value = Thread.current.threadDictionary[key] else {
                return defaultValue
            }
            guard let value = value as? Value else {
                owsFailDebug("Unexpected value: \(type(of: value))")
                return defaultValue
            }
            return value
        }
        set {
            Thread.current.threadDictionary[key] = newValue
        }
    }
}
