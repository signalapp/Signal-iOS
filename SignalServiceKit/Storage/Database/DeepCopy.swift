//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DeepCopyable {
    func deepCopy() throws -> AnyObject
}

// MARK: -

final public class DeepCopies {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {
    }

    static func deepCopy<T: DeepCopyable>(_ objectToCopy: T) throws -> T {
        guard let newCopy = try objectToCopy.deepCopy() as? T else {
            throw OWSAssertionError("Could not copy: \(type(of: objectToCopy))")
        }
        return newCopy
    }

    static func deepCopy<T: DeepCopyable>(_ arrayToCopy: [T]) throws -> [T] {
        return try arrayToCopy.deepCopy()
    }

    static func deepCopy<K: DeepCopyable, V: DeepCopyable>(_ dictToCopy: [K: V]) throws -> [K: V] {
        return try dictToCopy.deepCopy()
    }

    // Swift does not appear to offer a way to let Array conform
    // to DeepCopyable IFF Array.Element conforms to DeepCopyable.
    // This if unfortunate and poses a decision.
    //
    // We can makes Array generically conform to DeepCopyable,
    // but then we get not compile-time type checking.
    //
    // Instead we create a variety of specializations of
    // DeepCopies.deepCopy().  This is tedious but safer.
    static func deepCopy<K: DeepCopyable, V: DeepCopyable>(_ dictToCopy: [K: [V]]) throws -> [K: [V]] {
        return Dictionary(uniqueKeysWithValues: try dictToCopy.map({ (key, value) in
            let keyCopy: K = try DeepCopies.deepCopy(key)
            let valueCopy: [V] = try value.deepCopy()
            return (keyCopy, valueCopy)
        }))
    }

    // NOTE: We do not get compile-time type safety with Any.
    static func deepCopy(_ dictToCopy: [InfoMessageUserInfoKey: Any]) throws -> [InfoMessageUserInfoKey: Any] {
        return Dictionary(uniqueKeysWithValues: try dictToCopy.map({ (key, value) in
            let keyCopy: String = try DeepCopies.deepCopy(key.rawValue as String)
            let valueCopy: AnyObject
            if let objectToCopy = NSObject.asDeepCopyable(value) {
                valueCopy = try objectToCopy.deepCopy()
            } else {
                throw OWSAssertionError("Could not copy: \(type(of: value))")
            }
            return (InfoMessageUserInfoKey(rawValue: keyCopy), valueCopy)
        }))
    }

    // "Cannot explicitly specialize a generic function."
    fileprivate static func shallowCopy<T: NSObject & NSCopying>(_ objectToCopy: T) throws -> T {
        guard let newCopy = objectToCopy.copy() as? T else {
            throw OWSAssertionError("Could not copy: \(type(of: objectToCopy))")
        }
        return newCopy
    }
}

// MARK: -

extension Array where Element: DeepCopyable {
    public func deepCopy() throws -> [Element] {
        return try map { element in
            return try DeepCopies.deepCopy(element)
        }
    }
}

// MARK: -

extension Dictionary where Key: DeepCopyable, Value: DeepCopyable {
    public func deepCopy() throws -> [Key: Value] {
        return Dictionary(uniqueKeysWithValues: try self.map({ (key, value) in
            let keyCopy: Key = try DeepCopies.deepCopy(key)
            let valueCopy: Value = try DeepCopies.deepCopy(value)
            return (keyCopy, valueCopy)
        }))
    }
}

// MARK: -

extension NSNumber: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // No need to copy; NSNumber is immutable.
        return self
    }
}

// MARK: -

extension String: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self as NSString)
    }
}

// MARK: -

extension Data: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // No need to copy; Data is immutable.
        return self as NSData
    }
}

// MARK: -

@objc
extension StickerInfo: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension OWSGiftBadge: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension OWSLinkPreview: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension SignalServiceAddress: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension MessageSticker: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension TSQuotedMessage: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension OWSContact: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension StickerPackInfo: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension StickerPackItem: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension TSGroupModel: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension TSOutgoingMessageRecipientState: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension DisappearingMessageToken: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension ProfileChanges: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension MessageBodyRanges: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension TSPaymentNotification: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension TSArchivedPaymentInfo: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension MobileCoinPayment: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

@objc
extension TSInfoMessage.LegacyPersistableGroupUpdateItemsWrapper: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

@objc
extension TSInfoMessage.PersistableGroupUpdateItemsWrapper: DeepCopyable {
    public func deepCopy() throws -> AnyObject {
        // This class can use shallow copies.
        return try DeepCopies.shallowCopy(self)
    }
}

// MARK: -

extension NSObject {
    public static func asDeepCopyable(_ value: Any) -> DeepCopyable? {
        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return data
        }
        guard let deepCopyable = value as? DeepCopyable else {
            owsFailDebug("Could not copy: \(value)")
            return nil
        }
        return deepCopyable
    }
}
