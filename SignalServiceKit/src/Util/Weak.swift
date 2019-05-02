//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

/**
 * Container for a weakly referenced object.
 *
 * Only use this for |T| with reference-semantic entities
 * That is - <T> should inherit from AnyObject or Class-only protocols, but not structs or enums.
 *
 * Based on https://devforums.apple.com/message/981472#981472, but also supports class-only protocols
 */
public struct Weak<T> {
    private weak var _value: AnyObject?

    public var value: T? {
        get {
            return _value as? T
        }
        set {
            _value = newValue as AnyObject
        }
    }

    public init(value: T) {
        self.value = value
    }
}
