//
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

/**
 * Container for a weakly referenced object.
 *
 * Only use this for |T| with reference-semantic entities
 * e.g. inheriting from AnyObject or Class-only protocols, but not structs or enums.
 *
 *
 * Based on https://devforums.apple.com/message/981472#981472, but also supports class-only protocols
 */
struct Weak<T> {
    private weak var _value: AnyObject?

    var value: T? {
        get {
            return _value as? T
        }
        set {
            _value = newValue as AnyObject
        }
    }

    init(value: T) {
        self.value = value
    }
}
