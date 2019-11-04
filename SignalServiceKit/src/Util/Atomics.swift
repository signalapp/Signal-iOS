//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

enum AtomicError: Error {
    case invalidTransition
}

@objc
public class AtomicBool: NSObject {
    private var value: Bool

    @objc
    public required init(_ value: Bool) {
        self.value = value
    }

    // All instances can share a single queue.
    private static let serialQueue = DispatchQueue(label: "AtomicBool")

    @objc
    public func get() -> Bool {
        return AtomicBool.serialQueue.sync {
            return self.value
        }
    }

    @objc
    public func set(_ value: Bool) {
        return AtomicBool.serialQueue.sync {
            self.value = value
        }
    }

    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    @objc
    public func transition(from fromValue: Bool, to toValue: Bool) throws {
        return try AtomicBool.serialQueue.sync {
            guard self.value == fromValue else {
                throw AtomicError.invalidTransition
            }
            self.value = toValue
        }
    }
}
