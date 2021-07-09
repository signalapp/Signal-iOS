//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ThreadLocalFlag {
    private let key: String
    private let defaultValue: Bool

    public init(key: String, defaultValue: Bool = false) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var value: Bool {
        get {
            guard let value = Thread.current.threadDictionary[key] else {
                return defaultValue
            }
            guard let value = value as? Bool else {
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
